# frozen_string_literal: true

module Decidim
  module VolunteerScheduler
    # Base controller for the volunteer scheduler - organization level
    class ApplicationController < Decidim::ApplicationController
      include Decidim::UserBlockedChecker
      
      private
      
      def permission_class_chain
        [
          Decidim::VolunteerScheduler::Permissions,
          Decidim::Permissions
        ]
      end

      # Session-modifying callbacks should not interfere with CSRF protection
      # Since Decidim uses protect_from_forgery with prepend: true, our callbacks run after CSRF check
      before_action :store_referral_code
      before_action :ensure_volunteer_profile
      after_action :process_referral_signup, if: :current_user

      private

      def ensure_volunteer_profile
        return unless current_user&.confirmed?
        return if current_volunteer_profile
        
        Rails.logger.info "Creating volunteer profile for user: #{current_user.email}"
        
        # Create volunteer profile if it doesn't exist (organization-level)
        begin
          @current_volunteer_profile = VolunteerProfile.create!(
            user: current_user,
            organization: current_organization,
            level: 1,
            total_xp: 0,
            referral_code: generate_referral_code,
            activity_multiplier: 1.0
          )
          Rails.logger.info "✓ Volunteer profile created successfully"
        rescue => e
          Rails.logger.error "Failed to create volunteer profile: #{e.message}"
          raise e
        end
      end

      def generate_referral_code
        loop do
          code = SecureRandom.alphanumeric(8).upcase
          break code unless VolunteerProfile.exists?(
            referral_code: code,
            organization: current_organization
          )
        end
      end

      def current_volunteer_profile
        return nil unless current_user&.confirmed?
        
        @current_volunteer_profile ||= current_user.volunteer_profile
      end

      helper_method :current_volunteer_profile
      
      def store_referral_code
        if params[:ref].present?
          session[:referral_code] = params[:ref]
          Rails.logger.info "Stored referral code: #{params[:ref]} in session"
        end
      end

      def process_referral_signup
        return unless current_user&.confirmed?
        return unless session[:referral_code]
        return if current_volunteer_profile&.referrer
        
        referrer_profile = VolunteerProfile.find_by(
          referral_code: session[:referral_code],
          organization: current_organization
        )
        
        if referrer_profile && referrer_profile != current_volunteer_profile
          begin
            # Create the referral chain
            Referral.create_referral_chain(referrer_profile, current_volunteer_profile)
            Rails.logger.info "✓ Referral chain created for #{current_user.email} from #{referrer_profile.referral_code}"
            session.delete(:referral_code)
          rescue => e
            Rails.logger.error "Failed to create referral chain: #{e.message}"
            session.delete(:referral_code)
          end
        end
      end
    end
  end
end
