# app/models/decidim/volunteer_scheduler/task_template.rb
module Decidim
  module VolunteerScheduler
    class TaskTemplate < ApplicationRecord
      include Decidim::Resourceable
      include Decidim::HasComponent
      include Decidim::Traceable
      include Decidim::Loggable
      include Decidim::TranslatableResource
      
      self.table_name = "decidim_volunteer_scheduler_task_templates"
      
      component_manifest_name "volunteer_scheduler"
      
      has_many :task_assignments, dependent: :destroy, 
               class_name: "Decidim::VolunteerScheduler::TaskAssignment"
      
      enum level: { level1: 1, level2: 2, level3: 3 }
      enum frequency: { daily: 0, weekly: 1, monthly: 2, one_time: 3 }
      enum category: { 
        outreach: 0, technical: 1, administrative: 2, 
        creative: 3, research: 4, mentoring: 5 
      }
      
      translatable_fields :title, :description
      
      validates :title, translatable_presence: true, length: { maximum: 150 }
      validates :description, translatable_presence: true
      validates :xp_reward, numericality: { greater_than: 0, less_than: 1000 }
      validates :scicent_reward, numericality: { greater_than_or_equal_to: 0 }
      validates :level, presence: true
      validates :category, presence: true
      validates :frequency, presence: true
      
      scope :active, -> { where(active: true) }
      scope :available_for_level, ->(level) { where("level <= ?", level) }
      scope :by_category, ->(category) { where(category: category) }
      scope :available_now, -> { 
        where("(available_from IS NULL OR available_from <= ?) AND (available_until IS NULL OR available_until >= ?)", 
              Time.current, Time.current) 
      }
      scope :with_assignments_available, -> {
        left_joins(:task_assignments)
          .group(:id)
          .having("COUNT(decidim_volunteer_scheduler_task_assignments.id) < decidim_volunteer_scheduler_task_templates.max_assignments OR decidim_volunteer_scheduler_task_templates.max_assignments IS NULL")
      }
      
      def self.available_for_user(user)
        return none unless user&.volunteer_profile
        
        profile = user.volunteer_profile
        
        active
          .available_now
          .available_for_level(profile.level)
          .with_assignments_available
          .where.not(id: TaskAssignment.where(assignee: user, status: [:pending, :in_progress, :submitted]).select(:task_template_id))
      end
      
      def available_for_user?(user)
        return false unless user&.volunteer_profile
        return false unless active?
        return false if user.volunteer_profile.level < level.to_i
        return false if available_from && available_from > Time.current
        return false if available_until && available_until < Time.current
        return false if max_assignments && current_assignments_count >= max_assignments
        return false if user_has_active_assignment?(user)
        
        # Check if user meets any special requirements
        return false unless user_meets_requirements?(user)
        
        true
      end
      
      def due_date_for_assignment
        case frequency
        when "daily"
          1.day.from_now
        when "weekly"
          1.week.from_now
        when "monthly"
          1.month.from_now
        else
          available_until || 1.week.from_now
        end
      end
      
      def current_assignments_count
        task_assignments.where(status: [:pending, :in_progress, :submitted]).count
      end
      
      def completed_assignments_count
        task_assignments.where(status: :completed).count
      end
      
      def total_assignments_count
        task_assignments.count
      end
      
      def average_completion_time
        completed_assignments = task_assignments.where(status: :completed)
                                              .where.not(completed_at: nil, assigned_at: nil)
        
        return 0 if completed_assignments.empty?
        
        total_time = completed_assignments.sum { |a| (a.completed_at - a.assigned_at).to_f }
        (total_time / completed_assignments.count / 1.hour).round(2) # in hours
      end
      
      def success_rate
        return 0 if total_assignments_count == 0
        
        (completed_assignments_count.to_f / total_assignments_count * 100).round(2)
      end
      
      def can_be_assigned_to?(user)
        available_for_user?(user)
      end
      
      def level_name
        I18n.t("decidim.volunteer_scheduler.levels.level_#{level}")
      end
      
      def category_name
        I18n.t("decidim.volunteer_scheduler.categories.#{category}")
      end
      
      def frequency_name
        I18n.t("decidim.volunteer_scheduler.frequencies.#{frequency}")
      end
      
      private
      
      def user_has_active_assignment?(user)
        task_assignments.exists?(
          assignee: user, 
          status: [:pending, :in_progress, :submitted]
        )
      end
      
      def user_meets_requirements?(user)
        return true if requirements.blank?
        
        profile = user.volunteer_profile
        parsed_requirements = JSON.parse(requirements) rescue {}
        
        # Check minimum completed tasks
        if parsed_requirements["min_completed_tasks"]
          return false if profile.tasks_completed < parsed_requirements["min_completed_tasks"]
        end
        
        # Check required capabilities
        if parsed_requirements["required_capabilities"]
          required_caps = parsed_requirements["required_capabilities"]
          return false unless required_caps.all? { |cap| profile.can_access_capability?(cap) }
        end
        
        # Check minimum XP
        if parsed_requirements["min_xp"]
          return false if profile.total_xp < parsed_requirements["min_xp"]
        end
        
        true
      end
    end
    
    # app/models/decidim/volunteer_scheduler/task_assignment.rb
    class TaskAssignment < ApplicationRecord
      include Decidim::Traceable
      include Decidim::Loggable
      
      self.table_name = "decidim_volunteer_scheduler_task_assignments"
      
      belongs_to :task_template, class_name: "Decidim::VolunteerScheduler::TaskTemplate"
      belongs_to :assignee, class_name: "Decidim::User"
      belongs_to :reviewer, class_name: "Decidim::User", optional: true
      
      has_many :scicent_transactions, as: :source,
               class_name: "Decidim::VolunteerScheduler::ScicentTransaction"
      
      enum status: { 
        pending: 0, in_progress: 1, submitted: 2, 
        completed: 3, rejected: 4, cancelled: 5 
      }
      
      validates :assignee, presence: true
      validates :task_template, presence: true
      validates :assigned_at, presence: true
      validate :assignee_can_accept_task, on: :create
      validate :report_present_when_submitted
      
      scope :overdue, -> { 
        where("due_date < ? AND status IN (?)", 
              Time.current, [statuses[:pending], statuses[:in_progress]]) 
      }
      scope :due_soon, -> { 
        where("due_date BETWEEN ? AND ? AND status IN (?)", 
              Time.current, 1.day.from_now, [statuses[:pending], statuses[:in_progress]]) 
      }
      scope :recent, -> { order(assigned_at: :desc) }
      scope :by_status, ->(status) { where(status: status) }
      scope :for_user, ->(user) { where(assignee: user) }
      
      after_create :set_due_date
      after_update :process_status_change, if: :saved_change_to_status?
      
      def overdue?
        due_date && due_date < Time.current && !completed? && !rejected?
      end
      
      def due_soon?
        due_date && due_date <= 1.day.from_now && (pending? || in_progress?)
      end
      
      def days_until_due
        return nil unless due_date
        return 0 if overdue?
        
        ((due_date - Time.current) / 1.day).ceil
      end
      
      def can_be_started?
        pending?
      end
      
      def can_be_submitted?
        in_progress?
      end
      
      def can_be_completed?
        submitted? && report.present?
      end
      
      def start_task!
        return false unless can_be_started?
        
        update!(
          status: :in_progress,
          started_at: Time.current
        )
        
        trigger_task_started_event
      end
      
      def submit_task!(report_text, submission_data = {})
        return false unless can_be_submitted?
        return false if report_text.blank?
        
        update!(
          status: :submitted,
          report: report_text,
          submitted_at: Time.current,
          submission_data: submission_data
        )
        
        trigger_task_submitted_event
      end
      
      def complete_task!(reviewer_user, admin_notes = nil)
        return false unless can_be_completed?
        
        transaction do
          xp_earned = calculate_xp_reward
          scicent_earned = calculate_scicent_reward
          
          update!(
            status: :completed,
            completed_at: Time.current,
            reviewer: reviewer_user,
            admin_notes: admin_notes,
            xp_earned: xp_earned,
            scicent_earned: scicent_earned
          )
          
          # Update volunteer profile
          profile = assignee.volunteer_profile
          profile.add_xp(xp_earned)
          profile.add_scicent(scicent_earned, self)
          profile.increment_tasks_completed
          
          # Distribute referral commissions
          distribute_referral_commissions(scicent_earned)
          
          trigger_task_completed_event
        end
      end
      
      def reject_task!(reviewer_user, admin_notes)
        return false unless submitted?
        
        update!(
          status: :rejected,
          reviewer: reviewer_user,
          admin_notes: admin_notes
        )
        
        trigger_task_rejected_event
      end
      
      def cancel_task!(reason = nil)
        return false if completed?
        
        update!(
          status: :cancelled,
          admin_notes: reason
        )
        
        trigger_task_cancelled_event
      end
      
      def completion_time_hours
        return nil unless completed_at && assigned_at
        
        ((completed_at - assigned_at) / 1.hour).round(2)
      end
      
      def status_badge_class
        case status
        when 'pending' then 'secondary'
        when 'in_progress' then 'warning'
        when 'submitted' then 'primary'
        when 'completed' then 'success'
        when 'rejected' then 'alert'
        when 'cancelled' then 'secondary'
        else 'secondary'
        end
      end
      
      private
      
      def assignee_can_accept_task
        return unless task_template && assignee
        
        unless task_template.available_for_user?(assignee)
          errors.add(:assignee, "cannot accept this task")
        end
      end
      
      def report_present_when_submitted
        if status == 'submitted' && report.blank?
          errors.add(:report, "must be present when submitting task")
        end
      end
      
      def set_due_date
        self.due_date = task_template.due_date_for_assignment
        save! if persisted?
      end
      
      def process_status_change
        case status
        when 'in_progress'
          self.started_at = Time.current if started_at.blank?
        when 'submitted'
          self.submitted_at = Time.current if submitted_at.blank?
        when 'completed'
          process_completion if completed_at.present?
        end
      end
      
      def calculate_xp_reward
        base_xp = task_template.xp_reward
        multiplier = assignee.volunteer_profile.activity_multiplier
        (base_xp * multiplier).to_i
      end
      
      def calculate_scicent_reward
        base_scicent = task_template.scicent_reward
        multiplier = assignee.volunteer_profile.activity_multiplier
        base_scicent * multiplier
      end
      
      def distribute_referral_commissions(scicent_amount)
        return if scicent_amount <= 0
        
        # This will be handled by a background job for better performance
        ReferralCommissionJob.perform_later(assignee.id, scicent_amount)
      end
      
      def trigger_task_started_event
        Decidim::EventsManager.publish(
          event: "decidim.volunteer_scheduler.task_started",
          event_class: "Decidim::VolunteerScheduler::TaskStartedEvent",
          resource: self,
          affected_users: [assignee]
        )
      end
      
      def trigger_task_submitted_event
        Decidim::EventsManager.publish(
          event: "decidim.volunteer_scheduler.task_submitted",
          event_class: "Decidim::VolunteerScheduler::TaskSubmittedEvent",
          resource: self,
          affected_users: [assignee],
          followers: component.organization.admins
        )
      end
      
      def trigger_task_completed_event
        Decidim::EventsManager.publish(
          event: "decidim.volunteer_scheduler.task_completed",
          event_class: "Decidim::VolunteerScheduler::TaskCompletedEvent",
          resource: self,
          affected_users: [assignee],
          extra: {
            xp_earned: xp_earned,
            scicent_earned: scicent_earned
          }
        )
      end
      
      def trigger_task_rejected_event
        Decidim::EventsManager.publish(
          event: "decidim.volunteer_scheduler.task_rejected",
          event_class: "Decidim::VolunteerScheduler::TaskRejectedEvent",
          resource: self,
          affected_users: [assignee],
          extra: {
            rejection_reason: admin_notes
          }
        )
      end
      
      def trigger_task_cancelled_event
        Decidim::EventsManager.publish(
          event: "decidim.volunteer_scheduler.task_cancelled",
          event_class: "Decidim::VolunteerScheduler::TaskCancelledEvent",
          resource: self,
          affected_users: [assignee]
        )
      end
    end
  end
end