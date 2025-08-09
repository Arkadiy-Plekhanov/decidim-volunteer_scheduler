# frozen_string_literal: true

module Decidim
  module VolunteerScheduler
    # Base controller for the volunteer scheduler - organization level
    class ApplicationController < Decidim::ApplicationController
      include NeedsPermission

      register_permissions(::Decidim::VolunteerScheduler::Permissions,
                          ::Decidim::Permissions) if defined?(::Decidim::VolunteerScheduler::Permissions)

      # Session-modifying callbacks should not interfere with CSRF protection
      # Since Decidim uses protect_from_forgery with prepend: true, our callbacks run after CSRF check
      before_action :store_referral_code
      before_action :ensure_volunteer_profile
      after_action :process_referral_signup, if: :current_user

      private

      def ensure_volunteer_profile
        return unless current_user&.confirmed?
        return if current_volunteer_profile
        
        # Create volunteer profile if it doesn't exist (organization-level)
        @current_volunteer_profile = VolunteerProfile.create!(
          user: current_user,
          organization: current_organization
        )
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
          # Process referral signup using our referral system
          Rails.logger.info "Processing referral signup: #{session[:referral_code]}"
          session.delete(:referral_code)
        end
      end
    end
  end
end
