# frozen_string_literal: true

module Decidim
  module VolunteerScheduler
    module Admin
      # A command with all the business logic for creating a task template
      class CreateTaskTemplate < Decidim::Command
        # Public: Initializes the command.
        #
        # form - A form object with the params.
        # current_user - The current user creating the template
        def initialize(form, current_user)
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

          transaction do
            create_task_template!
            log_action
          end

          broadcast(:ok, task_template)
        end

        private

        attr_reader :form, :current_user, :task_template

        def create_task_template!
          @task_template = Decidim.traceability.create!(
            TaskTemplate,
            current_user,
            task_template_attributes,
            visibility: "admin-only"
          )
        end

        def task_template_attributes
          {
            organization: form.current_organization,
            component: form.current_component,
            title: form.title,
            description: form.description,
            xp_reward: form.xp_reward,
            scicent_reward: form.scicent_reward || 0,
            level_required: form.level_required,
            category: form.category,
            frequency: form.frequency,
            status: :draft,
            max_assignments_per_day: form.max_assignments_per_day,
            deadline_days: form.deadline_days || 7,
            instructions: form.instructions,
            metadata: {
              skills_required: form.skills_required,
              created_by_id: current_user.id,
              created_at: Time.current
            }
          }
        end

        def log_action
          Decidim::ActionLog.create!(
            organization: form.current_organization,
            user: current_user,
            participatory_space: form.current_participatory_space,
            component: form.current_component,
            action: "create",
            resource: task_template,
            resource_type: task_template.class.name,
            visibility: "admin-only",
            extra: {
              xp_reward: task_template.xp_reward,
              level_required: task_template.level_required
            }
          )
        end
      end
    end
  end
end