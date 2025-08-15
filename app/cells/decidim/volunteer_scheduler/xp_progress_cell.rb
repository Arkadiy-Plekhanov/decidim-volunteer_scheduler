# frozen_string_literal: true

module Decidim
  module VolunteerScheduler
    # Cell for rendering XP progress bars
    class XpProgressCell < Decidim::ViewModel
      def show
        return content_tag(:div, "No volunteer profile available", class: "callout warning") unless volunteer_profile
        render
      end

      private

      def volunteer_profile
        model
      end

      def progress_percentage
        return 0 unless volunteer_profile
        volunteer_profile.level_progress_percentage
      end

      def next_level_xp
        return 0 unless volunteer_profile
        volunteer_profile.next_level_xp
      end

      def current_level
        return 1 unless volunteer_profile
        volunteer_profile.level
      end

      def total_xp
        return 0 unless volunteer_profile
        volunteer_profile.total_xp
      end
    end
  end
end
