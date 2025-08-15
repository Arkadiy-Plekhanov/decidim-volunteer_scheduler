# frozen_string_literal: true

module Decidim
  module VolunteerScheduler
    # Cell for rendering volunteer profile statistics in a card format
    class ProfileStatsCell < Decidim::ViewModel
      def show
        render
      end

      private

      def volunteer_profile
        model
      end

      def stats_data
        [
          {
            icon: "checkbox-circle-line",
            value: volunteer_profile.level,
            label: t(".level"),
            color: level_color
          },
          {
            icon: "check-double-line", 
            value: volunteer_profile.total_xp,
            label: t(".total_xp"),
            color: "text-success"
          },
          {
            icon: "user-smile-line",
            value: referral_count,
            label: t(".referrals"),
            color: "text-primary"
          },
          {
            icon: "bubble-chart-line",
            value: "#{volunteer_profile.activity_multiplier.round(2)}x",
            label: t(".multiplier"),
            color: "text-info"
          }
        ]
      end

      def level_color
        case volunteer_profile.level
        when 1
          "text-warning"
        when 2
          "text-info"
        when 3
          "text-success"
        else
          "text-secondary"
        end
      end

      def referral_count
        # Placeholder - implement when referral system is ready
        0
      end

      def progress_percentage
        volunteer_profile.level_progress_percentage
      end

      def next_level_xp_needed
        volunteer_profile.next_level_xp
      end

      def current_level_xp
        case volunteer_profile.level
        when 1
          volunteer_profile.total_xp
        when 2
          volunteer_profile.total_xp - 100
        when 3
          volunteer_profile.total_xp - 500
        else
          0
        end
      end

      def referral_url(profile)
        # Use Decidim's organization-aware URL generation
        decidim.root_url(host: current_organization.host, ref: profile.referral_code)
      end
    end
  end
end