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
            icon: "trophy-line",
            value: volunteer_profile.level,
            label: t(".level"),
            secondary: level_name
          },
          {
            icon: "star-line",
            value: number_with_delimiter(volunteer_profile.total_xp),
            label: t(".total_xp"),
            secondary: xp_to_next_level_text
          },
          {
            icon: "user-smile-line",
            value: referral_count,
            label: t(".referrals"),
            secondary: t(".active_referrals")
          },
          {
            icon: "dashboard-line",
            value: "#{volunteer_profile.activity_multiplier.round(2)}x",
            label: t(".multiplier"),
            secondary: multiplier_status
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
        thresholds = volunteer_profile.level_thresholds
        current_threshold = volunteer_profile.level > 1 ? thresholds[volunteer_profile.level - 2] : 0

        volunteer_profile.total_xp - current_threshold
      end

      def referral_url(profile)
        # Use Decidim's organization-aware URL generation
        decidim.root_url(host: current_organization.host, ref: profile.referral_code)
      end

      def level_name
        case volunteer_profile.level
        when 1
          t(".beginner")
        when 2
          t(".intermediate")
        when 3
          t(".advanced")
        else
          t(".expert")
        end
      end

      def xp_to_next_level_text
        xp_needed = next_level_xp_needed
        return t(".max_level") if xp_needed.nil? || xp_needed <= 0

        t(".xp_to_next", xp: number_with_delimiter(xp_needed))
      end

      def multiplier_status
        multiplier = volunteer_profile.activity_multiplier
        if multiplier >= 2.0
          t(".high_activity")
        elsif multiplier >= 1.5
          t(".active")
        else
          t(".normal_activity")
        end
      end
    end
  end
end