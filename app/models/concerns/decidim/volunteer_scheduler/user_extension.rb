# frozen_string_literal: true

module Decidim
  module VolunteerScheduler
    # Extension for Decidim::User to automatically create volunteer profiles
    module UserExtension
      extend ActiveSupport::Concern

      included do
        has_one :volunteer_profile, 
                class_name: "Decidim::VolunteerScheduler::VolunteerProfile",
                foreign_key: :user_id,
                dependent: :destroy

        # Create volunteer profile after user is confirmed
        after_commit :create_volunteer_profile, on: :create, if: :should_create_volunteer_profile?
        after_commit :create_volunteer_profile_on_confirmation, on: :update, if: :just_confirmed?
      end

      private

      def should_create_volunteer_profile?
        # Create profile immediately for users who are already confirmed
        # (like those created via skip_confirmation! in seeds)
        confirmed? && !deleted? && !managed?
      end

      def just_confirmed?
        # Create profile when user confirms their email
        saved_change_to_confirmed_at? && confirmed? && !deleted? && !managed?
      end

      def create_volunteer_profile
        return if volunteer_profile.present?
        
        Rails.logger.info "Creating volunteer profile for user: #{email}"
        
        begin
          Decidim::VolunteerScheduler::VolunteerProfile.create!(
            user: self,
            organization: organization,
            level: 1,
            total_xp: 0,
            referral_code: generate_referral_code,
            activity_multiplier: 1.0
          )
          
          Rails.logger.info "✓ Volunteer profile created for user: #{email}"
        rescue => e
          Rails.logger.error "Failed to create volunteer profile for user #{email}: #{e.message}"
          # Don't raise error to prevent user creation from failing
        end
      end

      def create_volunteer_profile_on_confirmation
        create_volunteer_profile
      end

      def generate_referral_code
        loop do
          code = SecureRandom.alphanumeric(8).upcase
          break code unless Decidim::VolunteerScheduler::VolunteerProfile.exists?(
            referral_code: code,
            organization: organization
          )
        end
      end
    end
  end
end