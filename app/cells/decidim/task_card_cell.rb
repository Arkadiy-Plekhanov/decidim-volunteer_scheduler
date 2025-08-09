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
        
        @current_volunteer_profile ||= VolunteerProfile.find_by(
          user: current_user,
          component: task_template.component
        )
      end

      def accept_task_path
        Decidim::EngineRouter.main_proxy(task_template.component).task_assignments_path(task_template_id: task_template.id)
      end
    end
  end
end
