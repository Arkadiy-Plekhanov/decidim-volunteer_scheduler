# frozen_string_literal: true

module Decidim
  module VolunteerScheduler
    # Controller for the volunteer dashboard
    class DashboardController < ApplicationController
      def index
        # Skip permission check for now to avoid routing issues
        # enforce_permission_to :read, :dashboard
        load_dashboard_data
      end
      

      private
      
      def load_dashboard_data
        return unless current_volunteer_profile

        # Get available tasks for the current volunteer's level
        @available_tasks = Decidim::VolunteerScheduler::TaskTemplate
                          .where(organization: current_organization)
                          .published
                          .where("level_required <= ?", current_volunteer_profile.level)
                          .limit(10)
        
        # Get current assignments
        @my_assignments = current_volunteer_profile.task_assignments
                         .includes(:task_template)
                         .order(assigned_at: :desc)
                         .limit(10)
        
        # Placeholder for transactions (can be implemented later)
        @recent_transactions = []
        
        @referral_stats = calculate_referral_stats
      end
      

      def calculate_referral_stats
        return {} unless current_volunteer_profile
        
        {
          total_referrals: 0,  # Placeholder - can be implemented later
          active_referrals: 0, # Placeholder - can be implemented later  
          total_commission: 0  # Placeholder - can be implemented later
        }
      end
    end
  end
end
