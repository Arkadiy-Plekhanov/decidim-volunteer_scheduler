# frozen_string_literal: true

module Decidim
  module VolunteerScheduler
    # Background job for processing referral commissions
    class ReferralCommissionJob < ApplicationJob
      queue_as :default

      def perform(volunteer_profile_id, base_amount)
        volunteer_profile = VolunteerProfile.find(volunteer_profile_id)
        processor = ReferralProcessor.new(volunteer_profile, base_amount)
        processor.call
      rescue ActiveRecord::RecordNotFound => e
        Rails.logger.error "VolunteerProfile not found: #{e.message}"
      rescue StandardError => e
        Rails.logger.error "Error processing referral commissions: #{e.message}"
        raise e
      end
    end
  end
end
