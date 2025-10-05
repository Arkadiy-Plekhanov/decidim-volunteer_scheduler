# frozen_string_literal: true

module Decidim
  module VolunteerScheduler
    # Background job for calculating activity multipliers with rolling windows and decay
    class ActivityMultiplierCalculationJob < ApplicationJob
      queue_as :default

      # Recalculate activity multipliers for all active volunteers
      # This job should be scheduled to run daily
      def perform(organization_id: nil)
        @organization_id = organization_id
        
        Rails.logger.info "Starting activity multiplier calculation#{organization_id ? " for organization #{organization_id}" : ""}"
        
        profiles_to_update = volunteer_profiles_scope
        processed_count = 0
        
        profiles_to_update.find_each(batch_size: 100) do |profile|
          calculate_multiplier_for_profile(profile)
          processed_count += 1
        end
        
        Rails.logger.info "Activity multiplier calculation completed. Processed #{processed_count} profiles."
      rescue StandardError => e
        Rails.logger.error "Activity multiplier calculation failed: #{e.message}"
        Rails.logger.error e.backtrace.join("\n")
        raise e
      end

      private

      def volunteer_profiles_scope
        scope = Decidim::VolunteerScheduler::VolunteerProfile.includes(:user, :task_assignments, :scicent_transactions)
        scope = scope.joins(:user).where(users: { organization_id: @organization_id }) if @organization_id
        scope
      end

      def calculate_multiplier_for_profile(profile)
        Rails.logger.debug "Calculating multiplier for user: #{profile.user.name}"
        
        # Start with base multiplier
        multiplier = base_multiplier
        
        # Add level-based bonus
        multiplier += level_bonus(profile)
        
        # Add activity-based bonus (rolling 30-day window)
        multiplier += activity_bonus(profile)
        
        # Add referral-based bonus
        multiplier += referral_bonus(profile)
        
        # Apply decay for inactivity
        multiplier = apply_inactivity_decay(profile, multiplier)
        
        # Cap at maximum multiplier
        final_multiplier = [multiplier, max_multiplier].min
        
        # Update profile if changed
        if (profile.activity_multiplier - final_multiplier).abs > 0.01
          old_multiplier = profile.activity_multiplier
          profile.update!(
            activity_multiplier: final_multiplier,
            last_multiplier_calculation: Time.current
          )
          
          Rails.logger.debug "Updated multiplier for #{profile.user.name}: #{old_multiplier} → #{final_multiplier}"
        end
      rescue StandardError => e
        Rails.logger.error "Failed to calculate multiplier for profile #{profile.id}: #{e.message}"
      end

      def base_multiplier
        1.0
      end

      def max_multiplier
        3.0
      end

      def level_bonus(profile)
        # +0.1x per level above 1
        (profile.level - 1) * 0.1
      end

      def activity_bonus(profile)
        # Count tasks approved in the last 30 days
        thirty_days_ago = 30.days.ago
        completed_tasks = profile.task_assignments
                                .approved
                                .where('reviewed_at > ?', thirty_days_ago)
                                .count

        # +0.05x per 10 completed tasks (with diminishing returns)
        task_groups = completed_tasks / 10
        case task_groups
        when 0
          0.0
        when 1..2
          task_groups * 0.05
        when 3..5
          0.10 + (task_groups - 2) * 0.03 # Reduced bonus after 20 tasks
        else
          0.19 + (task_groups - 5) * 0.01 # Further reduced after 50 tasks
        end
      end

      def referral_bonus(profile)
        # Count active referrals (active within 30 days)
        active_referrals = profile.active_referrals_count
        
        # +0.02x per active referral, up to 10 referrals
        bonus_referrals = [active_referrals, 10].min
        bonus_referrals * 0.02
      end

      def apply_inactivity_decay(profile, current_multiplier)
        return current_multiplier unless profile.last_activity_at
        
        days_inactive = (Time.current - profile.last_activity_at) / 1.day
        
        # Apply decay after 7 days of inactivity
        if days_inactive > 7
          # 5% decay per week of inactivity (exponential decay)
          weeks_inactive = days_inactive / 7.0
          decay_factor = 0.95 ** weeks_inactive
          
          # Don't decay below base multiplier + level bonus
          minimum_multiplier = base_multiplier + level_bonus(profile)
          [current_multiplier * decay_factor, minimum_multiplier].max
        else
          current_multiplier
        end
      end

      # Calculate rolling activity score for more sophisticated multipliers
      def calculate_rolling_activity_score(profile)
        thirty_days_ago = 30.days.ago
        
        # Weight different activities
        activity_score = 0.0
        
        # Task completions (main activity)
        completed_tasks = profile.task_assignments
                                .approved
                                .where('reviewed_at > ?', thirty_days_ago)
        
        completed_tasks.each do |assignment|
          days_ago = (Time.current - assignment.reviewed_at) / 1.day
          # More recent activities have higher weight
          recency_weight = [1.0 - (days_ago / 30.0), 0.1].max
          task_weight = assignment.task_template&.level_required || 1
          
          activity_score += recency_weight * task_weight * 1.0
        end
        
        # Token transactions (secondary activity)
        transactions = profile.scicent_transactions
                              .where('created_at > ?', thirty_days_ago)
                              .where.not(transaction_type: 'referral_commission')
        
        transactions.each do |transaction|
          days_ago = (Time.current - transaction.created_at) / 1.day
          recency_weight = [1.0 - (days_ago / 30.0), 0.1].max
          
          activity_score += recency_weight * 0.1 # Lower weight for transactions
        end
        
        activity_score
      end
    end
  end
end