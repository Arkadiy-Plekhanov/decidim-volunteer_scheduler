# frozen_string_literal: true

module Decidim
  module VolunteerScheduler
    # Cell for rendering XP progress bars
    class XpProgressCell < Decidim::ViewModel
      def show
        render
      end

      private

      def volunteer_profile
        model
      end

      def progress_percentage
        volunteer_profile.level_progress_percentage
      end

      def next_level_xp
        volunteer_profile.next_level_xp
      end

      def current_level
        volunteer_profile.level
      end

      def total_xp
        volunteer_profile.total_xp
      end
    end
  end
end
