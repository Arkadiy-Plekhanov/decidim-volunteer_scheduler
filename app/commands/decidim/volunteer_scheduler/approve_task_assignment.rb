# frozen_string_literal: true

module Decidim
  module VolunteerScheduler
    # A command with all the business logic for approving a task assignment
    class ApproveTaskAssignment < Decidim::Command
      # Public: Initializes the command.
      #
      # task_assignment - The task assignment to approve
      # form - A form object with admin notes
      # current_user - The admin user approving
      def initialize(task_assignment, form, current_user)
        @task_assignment = task_assignment
        @form = form
        @current_user = current_user
      end

      # Executes the command. Broadcasts these events:
      #
      # - :ok when everything is valid.
      # - :invalid if the form was not valid and we could not proceed.
      #
      # Returns nothing.
      def call
        return broadcast(:invalid) if form.invalid?
        return broadcast(:invalid_status) unless task_assignment.submitted?

        transaction do
          approve_assignment!
          award_xp!
          process_referral_rewards!
          send_notification
          log_action
        end

        broadcast(:ok, task_assignment)
      end

      private

      attr_reader :task_assignment, :form, :current_user

      def approve_assignment!
        task_assignment.update!(
          status: :approved,
          reviewed_at: Time.current,
          reviewer: current_user,
          admin_notes: form.admin_notes
        )
      end

      def award_xp!
        volunteer_profile = task_assignment.assignee
        xp_amount = calculate_xp_with_multiplier
        
        volunteer_profile.add_xp(xp_amount)
        
        # Create XP transaction record
        ScicentTransaction.create!(
          user: volunteer_profile.user,
          transaction_type: :task_reward,
          amount: xp_amount,
          status: :completed,
          reference: task_assignment,
          metadata: {
            task_id: task_assignment.id,
            base_xp: task_assignment.task_template.xp_reward,
            multiplier: volunteer_profile.activity_multiplier
          }
        )
      end

      def calculate_xp_with_multiplier
        base_xp = task_assignment.task_template.xp_reward
        multiplier = task_assignment.assignee.activity_multiplier
        (base_xp * multiplier).round
      end

      def process_referral_rewards!
        # Process referral chain rewards if enabled
        return unless component_settings.referral_rewards_enabled

        ReferralProcessor.new(task_assignment).process_rewards!
      end

      def send_notification
        Decidim::EventsManager.publish(
          event: "decidim.volunteer_scheduler.task_approved",
          event_class: Decidim::VolunteerScheduler::TaskApprovedEvent,
          resource: task_assignment,
          affected_users: [task_assignment.assignee.user],
          extra: {
            xp_awarded: calculate_xp_with_multiplier,
            admin_notes: form.admin_notes
          }
        )
      end

      def log_action
        Decidim::ActionLog.create!(
          organization: task_assignment.organization,
          user: current_user,
          participatory_space: task_assignment.participatory_space,
          component: task_assignment.component,
          action: "approve",
          resource: task_assignment,
          resource_type: task_assignment.class.name,
          visibility: "admin-only",
          extra: {
            reviewer_id: current_user.id,
            xp_awarded: calculate_xp_with_multiplier
          }
        )
      end

      def component_settings
        @component_settings ||= task_assignment.component.settings
      end
    end
  end
end