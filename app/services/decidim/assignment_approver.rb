# frozen_string_literal: true

module Decidim
  module VolunteerScheduler
    # Service for approving/rejecting task assignments and processing rewards
    class AssignmentApprover
      def initialize(assignment, reviewer, action, notes = nil)
        @assignment = assignment
        @reviewer = reviewer
        @action = action
        @notes = notes
      end

      def call
        return false unless valid?
        
        case @action
        when :approve
          approve_assignment
        when :reject
          reject_assignment
        else
          false
        end
      end

      private

      def valid?
        @assignment.can_be_reviewed? && 
        (@action == :approve || @action == :reject) &&
        @reviewer.present?
      end

      def approve_assignment
        ActiveRecord::Base.transaction do
          @assignment.approve!(@reviewer, @notes)
          process_xp_reward
          process_referral_commissions
          schedule_activity_multiplier_update
          
          log_approval
          true
        end
      rescue StandardError => e
        Rails.logger.error "Failed to approve assignment #{@assignment.id}: #{e.message}"
        false
      end

      def reject_assignment
        @assignment.reject!(@reviewer, @notes)
        log_rejection
        true
      rescue StandardError => e
        Rails.logger.error "Failed to reject assignment #{@assignment.id}: #{e.message}"
        false
      end

      def process_xp_reward
        xp_amount = @assignment.task_template.xp_reward
        @assignment.assignee.add_xp(xp_amount)
        
        ScicentTransaction.create_task_completion!(
          @assignment.assignee,
          xp_amount,
          @assignment.task_template.title
        )
      end

      def process_referral_commissions
        return unless @assignment.assignee.referrer
        
        Decidim::VolunteerScheduler::ReferralCommissionJob.perform_later(
          @assignment.assignee.id,
          @assignment.task_template.xp_reward
        )
      end

      def schedule_activity_multiplier_update
        Decidim::VolunteerScheduler::ActivityMultiplierJob.perform_later(
          @assignment.assignee.id
        )
      end

      def log_approval
        Decidim.traceability.perform_action!(
          "approve",
          @assignment,
          @reviewer,
          extra: {
            xp_awarded: @assignment.task_template.xp_reward,
            notes: @notes
          }
        )
      end

      def log_rejection
        Decidim.traceability.perform_action!(
          "reject",
          @assignment,
          @reviewer,
          extra: {
            notes: @notes
          }
        )
      end
    end
  end
end
