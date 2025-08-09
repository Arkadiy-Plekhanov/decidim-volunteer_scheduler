# frozen_string_literal: true

module Decidim
  module VolunteerScheduler
    module Admin
      # Controller for viewing volunteer profiles in admin interface
      class VolunteerProfilesController < ApplicationController
        before_action :set_volunteer_profile, only: [:show]

        def index
          @volunteer_profiles = VolunteerProfile.where(organization: current_organization)
                                              .includes(:user)
                                              .order(total_xp: :desc)
                                              .page(params[:page])

          @volunteer_profiles = @volunteer_profiles.by_level(params[:level]) if params[:level].present?
        end

        def show
          @recent_assignments = @volunteer_profile.task_assignments
                                                .includes(:task_template)
                                                .order(assigned_at: :desc)
                                                .limit(10)
          
          @recent_transactions = @volunteer_profile.scicent_transactions
                                                 .order(created_at: :desc)
                                                 .limit(10)
          
          @referral_tree = build_referral_tree
        end

        private

        def set_volunteer_profile
          @volunteer_profile = VolunteerProfile.where(organization: current_organization).find(params[:id])
        end

        def build_referral_tree
          referrals = Referral.where(referrer: @volunteer_profile)
                             .includes(:referred)
                             .order(:level, :created_at)
          
          tree = {}
          referrals.each do |referral|
            tree[referral.level] ||= []
            tree[referral.level] << referral
          end
          
          tree
        end
      end
    end
  end
end
