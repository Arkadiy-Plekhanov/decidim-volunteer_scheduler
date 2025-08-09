# frozen_string_literal: true

module Decidim
  module VolunteerScheduler
    # Background job for updating activity multipliers
    # Implements retry strategies and proper error handling per Decidim patterns
    class ActivityMultiplierJob < ApplicationJob
      queue_as :volunteer_scheduler_low
      
      # Retry configuration based on Decidim best practices
      retry_on ActiveRecord::RecordNotFound, wait: 5.seconds, attempts: 3
      retry_on ActiveRecord::ConnectionTimeoutError, wait: :exponentially_longer, attempts: 5
      
      # Prevent job spam
      discard_on ActiveJob::DeserializationError do |job, error|
        Rails.logger.error "[ActivityMultiplierJob] Deserialization failed: #{error.message}"
      end

      def perform(volunteer_profile_id)
        volunteer_profile = VolunteerProfile.find(volunteer_profile_id)
        
        # Use transaction to ensure consistency
        volunteer_profile.transaction do
          volunteer_profile.calculate_activity_multiplier!
          
          # Track calculation in metadata
          volunteer_profile.update_column(:metadata, 
            volunteer_profile.metadata.merge(
              "last_multiplier_update" => Time.current.iso8601,
              "update_source" => "scheduled_job"
            )
          )
        end
        
        # Queue referral chain updates as separate jobs to avoid timeout
        queue_referral_chain_updates(volunteer_profile)
        
        Rails.logger.info "[ActivityMultiplierJob] Updated profile ##{volunteer_profile_id}, multiplier: #{volunteer_profile.activity_multiplier}"
      rescue ActiveRecord::RecordNotFound => e
        Rails.logger.error "[ActivityMultiplierJob] VolunteerProfile ##{volunteer_profile_id} not found: #{e.message}"
        # Don't re-raise as retry_on handles this
      rescue StandardError => e
        Rails.logger.error "[ActivityMultiplierJob] Error for profile ##{volunteer_profile_id}: #{e.message}"
        Rails.logger.error e.backtrace.first(5).join("\n")
        raise # Re-raise for retry mechanism
      end

      private

      def queue_referral_chain_updates(volunteer_profile)
        # Queue updates for referrers (up the chain) as separate jobs
        referrer_ids = []
        current_profile = volunteer_profile
        
        5.times do
          referrer = Referral.where(referred: current_profile.user).first&.referrer
          break unless referrer
          
          referrer_ids << referrer.id
          current_profile = referrer
        end
        
        # Queue updates for referred users (down the chain)
        referred_ids = volunteer_profile.referrals_made
                                       .includes(:referred)
                                       .pluck("decidim_users.id")
        
        # Queue all updates with delay to prevent overload
        (referrer_ids + referred_ids).each_with_index do |profile_id, index|
          ActivityMultiplierJob.set(wait: (index * 2).seconds)
                              .perform_later(profile_id)
        end
      end
    end
  end
end
