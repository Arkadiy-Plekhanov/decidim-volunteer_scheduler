# frozen_string_literal: true

module Decidim
  module VolunteerScheduler
    # Cell for rendering the volunteer dashboard
    class DashboardCell < Decidim::ViewModel
      def show
        render
      end

      private

      def volunteer_profile
        model
      end

      def available_tasks
        volunteer_profile.available_tasks.limit(5)
      end

      def recent_assignments
        volunteer_profile.task_assignments
                        .includes(:task_template)
                        .recent
                        .limit(5)
      end

      def xp_progress_percentage
        volunteer_profile.level_progress_percentage
      end

      def next_level_xp
        volunteer_profile.next_level_xp
      end
    end
  end
end
