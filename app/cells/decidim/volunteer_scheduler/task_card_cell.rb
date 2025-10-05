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

      def already_accepted?
        return false unless current_volunteer_profile

        # Check if user already has an active assignment for this task
        current_volunteer_profile.task_assignments
                                 .where(task_template: task_template)
                                 .where.not(status: [:rejected, :completed])
                                 .exists?
      end

      def current_volunteer_profile
        return nil unless current_user&.confirmed?
        
        # Organization-level profiles
        @current_volunteer_profile ||= current_user.volunteer_profile
      end

      def accept_task_path
        # Use engine route helpers within the engine context
        accept_task_template_path(task_template.id)
      end

      def difficulty_class
        case task_template.level_required
        when 1
          "beginner"
        when 2
          "intermediate"
        when 3
          "advanced"
        else
          ""
        end
      end

      def difficulty_label
        case task_template.level_required
        when 1
          t(".beginner", default: "Beginner")
        when 2
          t(".intermediate", default: "Intermediate")
        when 3
          t(".advanced", default: "Advanced")
        else
          t(".unknown", default: "Unknown")
        end
      end

      def xp_badge_color
        if task_template.xp_reward >= 50
          "bg-purple-100 text-purple-800"
        elsif task_template.xp_reward >= 25
          "bg-blue-100 text-blue-800"
        else
          "bg-gray-100 text-gray-800"
        end
      end

      def estimated_time
        # Estimate based on XP reward and level
        min_abbr = I18n.t("decidim.volunteer_scheduler.common.minutes")
        case task_template.level_required
        when 1
          "5-10 #{min_abbr}"
        when 2
          "15-30 #{min_abbr}"
        when 3
          "30-60 #{min_abbr}"
        else
          I18n.t("decidim.volunteer_scheduler.task_card.unknown", default: "Unknown")
        end
      end
    end
  end
end
