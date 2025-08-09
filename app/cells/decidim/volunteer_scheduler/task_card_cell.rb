# frozen_string_literal: true

module Decidim
  module VolunteerScheduler
    # Cell for rendering task template cards
    class TaskCardCell < Decidim::ViewModel
      def show
        render
      end

      private

      def task_template
        model
      end

      def can_accept?
        return false unless current_user&.confirmed?
        return false unless current_volunteer_profile
        
        task_template.can_be_assigned_to?(current_volunteer_profile)
      end

      def current_volunteer_profile
        return nil unless current_user&.confirmed?
        
        # Organization-level profiles
        @current_volunteer_profile ||= current_user.volunteer_profile
      end

      def accept_task_path
        # Organization-level routing - use engine route helper
        # Using the task_template member route for accept
        Decidim::VolunteerScheduler::Engine.routes.url_helpers.accept_task_template_path(task_template.id)
      end
    end
  end
end
