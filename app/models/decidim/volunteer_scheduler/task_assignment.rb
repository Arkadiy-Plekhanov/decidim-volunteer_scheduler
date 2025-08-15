# frozen_string_literal: true

module Decidim
  module VolunteerScheduler
    # Model representing a task assignment to a volunteer
    class TaskAssignment < ApplicationRecord
      include Decidim::Followable
      include Decidim::Traceable
      include Decidim::Loggable

      # Organization-level assignments - no component association needed
      # belongs_to :decidim_component, class_name: "Decidim::Component", optional: true
      belongs_to :task_template, class_name: "Decidim::VolunteerScheduler::TaskTemplate", counter_cache: :task_assignments_count
      belongs_to :assignee, class_name: "Decidim::VolunteerScheduler::VolunteerProfile"
      belongs_to :reviewer, class_name: "Decidim::User", optional: true

      validates :status, presence: true
      validates :assigned_at, presence: true

      enum status: { pending: 0, submitted: 1, approved: 2, rejected: 3 }

      scope :for_volunteer, ->(volunteer) { where(assignee: volunteer) }
      scope :overdue, -> { where("due_date < ? AND status IN (?)", Time.current, [statuses[:pending], statuses[:submitted]]) }
      scope :recent, -> { where("assigned_at > ?", 30.days.ago) }

      before_validation :set_defaults, on: :create
      after_update :process_status_change, if: :saved_change_to_status?

      def overdue?
        due_date && due_date < Time.current && !approved?
      end

      def days_until_due
        return nil unless due_date
        
        ((due_date - Time.current) / 1.day).ceil
      end

      def completion_time_days
        return nil unless submitted_at && assigned_at
        
        ((submitted_at - assigned_at) / 1.day).round(1)
      end

      def can_be_submitted?
        pending? && !overdue?
      end

      def can_be_reviewed?
        submitted?
      end

      def latest_submission
        submission_data if submitted_at.present?
      end
      
      def submit_work!(submission_params = {})
        return false unless can_be_submitted?
        
        transaction do
          # Store submission data
          self.submitted_at = Time.current
          self.submission_notes = submission_params[:notes]
          self.submission_data = {
            hours_worked: submission_params[:hours_worked],
            challenges_faced: submission_params[:challenges_faced],
            attachments: submission_params[:attachments] || [],
            submitted_at: Time.current.iso8601
          }
          self.status = :submitted
          
          save!
        end
      end

      def approve!(reviewer_user, review_notes = nil)
        return false unless can_be_reviewed?
        
        transaction do
          self.status = :approved
          self.reviewed_at = Time.current
          self.reviewer = reviewer_user
          self.review_notes = review_notes
          
          save!
          
          # Award XP to volunteer
          assignee.add_xp(task_template.xp_reward)
          
          # Create transaction record
          ScicentTransaction.create_task_completion!(
            assignee,
            task_template.xp_reward,
            task_template.title
          )
          
          # Process referral commissions
          Decidim::VolunteerScheduler::ReferralCommissionJob.perform_later(assignee.id, task_template.xp_reward)
        end
        
        send_approval_notification
        true
      end

      def reject!(reviewer_user, review_notes = nil)
        return false unless can_be_reviewed?
        
        self.status = :rejected
        self.reviewed_at = Time.current
        self.reviewer = reviewer_user
        self.review_notes = review_notes
        
        save!
        send_rejection_notification
        true
      end

      private

      def set_defaults
        self.assigned_at ||= Time.current
        # Use organization-level default deadline (no component settings)
        deadline_days = 7
        self.due_date ||= assigned_at + deadline_days.days
      end

      def process_status_change
        case status
        when "submitted"
          send_submission_notification
        when "approved"
          # XP award is handled by approve! method, not here
          # assignee.add_xp(task_template.xp_reward) # REMOVED - duplicate
          send_approval_notification
        end
      end

      def send_submission_notification
        Decidim::EventsManager.publish(
          event: "decidim.volunteer_scheduler.task_assignment.submitted",
          event_class: Decidim::VolunteerScheduler::TaskSubmittedEvent,
          resource: self,
          affected_users: component_admins
        )
      end

      def send_approval_notification
        Decidim::EventsManager.publish(
          event: "decidim.volunteer_scheduler.task_assignment.approved",
          event_class: Decidim::VolunteerScheduler::TaskApprovedEvent,
          resource: self,
          affected_users: [assignee.user]
        )
      end

      def send_rejection_notification
        Decidim::EventsManager.publish(
          event: "decidim.volunteer_scheduler.task_assignment.rejected",
          event_class: Decidim::VolunteerScheduler::TaskRejectedEvent,
          resource: self,
          affected_users: [assignee.user]
        )
      end

      def component_admins
        # Organization-level operation - use organization admins
        task_template.organization.admins
      end
      
      
      def notify_submission
        Decidim::EventsManager.publish(
          event: "decidim.volunteer_scheduler.task_submitted",
          event_class: Decidim::VolunteerScheduler::TaskSubmittedEvent,
          resource: self,
          affected_users: component_admins
        )
      end
      
      def notify_approval
        Decidim::EventsManager.publish(
          event: "decidim.volunteer_scheduler.task_approved",
          event_class: Decidim::VolunteerScheduler::TaskApprovedEvent,
          resource: self,
          affected_users: [assignee.user]
        )
      end
    end
  end
end
