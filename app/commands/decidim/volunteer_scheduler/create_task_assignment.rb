# frozen_string_literal: true

module Decidim
  module VolunteerScheduler
    # A command with all the business logic for creating a task assignment
    class CreateTaskAssignment < Decidim::Command
      # Public: Initializes the command.
      #
      # form - A form object with the params.
      # task_template - The task template to assign
      # volunteer_profile - The volunteer profile to assign to
      def initialize(form, task_template, volunteer_profile)
        @form = form
        @task_template = task_template
        @volunteer_profile = volunteer_profile
      end

      # Executes the command. Broadcasts these events:
      #
      # - :ok when everything is valid.
      # - :invalid if the form was not valid and we could not proceed.
      #
      # Returns nothing.
      def call
        return broadcast(:invalid) if form.invalid?
        return broadcast(:level_insufficient) unless volunteer_can_accept_task?
        return broadcast(:max_tasks_reached) if max_tasks_reached?

        transaction do
          create_task_assignment!
          send_notification
          increment_metrics
        end

        broadcast(:ok, task_assignment)
      end

      private

      attr_reader :form, :task_template, :volunteer_profile, :task_assignment

      def volunteer_can_accept_task?
        volunteer_profile.level >= task_template.level_required
      end

      def max_tasks_reached?
        active_assignments_count >= max_daily_tasks
      end

      def active_assignments_count
        @active_assignments_count ||= TaskAssignment
                                      .where(assignee: volunteer_profile)
                                      .where(status: [:pending, :submitted])
                                      .where("assigned_at >= ?", 24.hours.ago)
                                      .count
      end

      def max_daily_tasks
        form.current_component.settings.max_daily_tasks || 5
      end

      def create_task_assignment!
        @task_assignment = TaskAssignment.create!(
          task_template: task_template,
          assignee: volunteer_profile,
          component: form.current_component,
          status: :pending,
          assigned_at: Time.current,
          due_date: Time.current + task_template.deadline_days.days
        )
      end

      def send_notification
        Decidim::EventsManager.publish(
          event: "decidim.volunteer_scheduler.task_assigned",
          event_class: Decidim::VolunteerScheduler::TaskAssignedEvent,
          resource: task_assignment,
          affected_users: [volunteer_profile.user],
          extra: {
            task_title: task_template.title,
            due_date: task_assignment.due_date
          }
        )
      end

      def increment_metrics
        # Track task assignment metrics for dashboard
        Decidim::ActionLog.create!(
          organization: form.current_organization,
          user: volunteer_profile.user,
          participatory_space: form.current_participatory_space,
          component: form.current_component,
          action: "create",
          resource: task_assignment,
          resource_type: task_assignment.class.name,
          visibility: "public-only"
        )
      end
    end
  end
end