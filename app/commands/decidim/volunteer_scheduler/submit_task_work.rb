# frozen_string_literal: true

module Decidim
  module VolunteerScheduler
    # Command to submit task work using the follow-up system
    class SubmitTaskWork < Decidim::Command
      # Public: Initializes the command.
      #
      # form - A form object with the submission data
      # current_user - The user submitting the task
      # assignment - The task assignment to submit
      def initialize(form, current_user, assignment)
        @form = form
        @current_user = current_user
        @assignment = assignment
      end

      # Executes the command. Broadcasts these events:
      #
      # - :ok when everything is valid.
      # - :invalid if the form was not valid and we could not proceed.
      #
      # Returns nothing.
      def call
        return broadcast(:invalid) if form.invalid?
        return broadcast(:invalid) unless assignment.can_be_submitted?
        return broadcast(:invalid) unless assignment.assignee.user == current_user

        transaction do
          submit_assignment
          create_follow_up
          notify_admins
        end

        broadcast(:ok, assignment)
      rescue ActiveRecord::RecordInvalid => e
        broadcast(:invalid)
      end

      private

      attr_reader :form, :current_user, :assignment

      def submit_assignment
        submission_params = {
          notes: form.report,
          hours_worked: form.hours_worked,
          challenges_faced: form.challenges_faced,
          attachments: form.attachment_ids
        }
        
        @follow_up = assignment.submit_work!(submission_params)
      end

      def create_follow_up
        # Additional follow-up tracking if needed
        Decidim.traceability.perform_action!(
          "submit",
          assignment,
          current_user,
          extra: {
            task_title: assignment.task_template.title,
            hours_worked: form.hours_worked
          }
        )
      end

      def notify_admins
        # Notification is handled in the model's submit_work! method
      end
    end
  end
end