# frozen_string_literal: true

module Decidim
  module VolunteerScheduler
    # Background job for updating activity multipliers
    class ActivityMultiplierJob < ApplicationJob
      queue_as :default

      def perform(volunteer_profile_id)
        volunteer_profile = VolunteerProfile.find(volunteer_profile_id)
        volunteer_profile.calculate_activity_multiplier!
        
        # Also update multipliers for the referral chain
        update_referral_chain_multipliers(volunteer_profile)
      rescue ActiveRecord::RecordNotFound => e
        Rails.logger.error "VolunteerProfile not found: #{e.message}"
      rescue StandardError => e
        Rails.logger.error "Error updating activity multipliers: #{e.message}"
        raise e
      end

      private

      def update_referral_chain_multipliers(volunteer_profile)
        # Update multipliers for referrers (up the chain)
        current_profile = volunteer_profile
        5.times do
          break unless current_profile.referrer
          
          current_profile.referrer.calculate_activity_multiplier!
          current_profile = current_profile.referrer
        end
        
        # Update multipliers for referred volunteers (down the chain)
        volunteer_profile.referrals_made.includes(:referred).each do |referral|
          referral.referred.calculate_activity_multiplier!
        end
      end
    end
  end
end
