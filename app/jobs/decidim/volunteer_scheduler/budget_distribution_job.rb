# frozen_string_literal: true

module Decidim
  module VolunteerScheduler
    # Background job for distributing monthly/weekly/daily budget pools to volunteers
    class BudgetDistributionJob < ApplicationJob
      queue_as :default

      # Distribute budget pool to top-performing volunteers
      # @param period_type [String] 'daily', 'weekly', or 'monthly'
      # @param organization_id [Integer] Organization to distribute budget for
      # @param pool_amount [Float] Total budget amount to distribute
      def perform(period_type, organization_id, pool_amount)
        @period_type = period_type
        @organization_id = organization_id
        @pool_amount = pool_amount.to_f
        @organization = Decidim::Organization.find(@organization_id)
        
        Rails.logger.info "Starting #{@period_type} budget distribution: #{@pool_amount} tokens for organization #{@organization_id}"
        
        return if @pool_amount <= 0
        
        # Get eligible volunteers for this period
        eligible_volunteers = get_eligible_volunteers
        
        if eligible_volunteers.empty?
          Rails.logger.warn "No eligible volunteers found for #{@period_type} budget distribution"
          return
        end
        
        # Distribute budget based on performance and activity
        distribute_budget(eligible_volunteers)
        
        Rails.logger.info "#{@period_type.capitalize} budget distribution completed: #{@pool_amount} tokens distributed"
      rescue StandardError => e
        Rails.logger.error "Budget distribution failed: #{e.message}"
        Rails.logger.error e.backtrace.join("\n")
        raise e
      end

      private

      def get_eligible_volunteers
        period_start = period_start_date
        
        # Get volunteers who were active during the period
        Decidim::VolunteerScheduler::VolunteerProfile
          .joins(:user)
          .where(users: { organization: @organization })
          .joins(:task_assignments)
          .where(
            decidim_volunteer_scheduler_task_assignments: {
              status: 'approved',
              reviewed_at: period_start..Time.current
            }
          )
          .group('decidim_volunteer_scheduler_volunteer_profiles.id')
          .having('COUNT(decidim_volunteer_scheduler_task_assignments.id) >= ?', minimum_tasks_for_period)
          .includes(:user, :task_assignments, :scicent_transactions)
      end

      def distribute_budget(volunteers)
        # Calculate performance scores for all volunteers
        volunteer_scores = calculate_performance_scores(volunteers)
        
        # Sort by performance score (descending)
        ranked_volunteers = volunteer_scores.sort_by { |_, score| -score }
        
        case @period_type
        when 'daily'
          distribute_daily_budget(ranked_volunteers)
        when 'weekly'
          distribute_weekly_budget(ranked_volunteers)
        when 'monthly'
          distribute_monthly_budget(ranked_volunteers)
        end
      end

      def calculate_performance_scores(volunteers)
        period_start = period_start_date
        scores = {}
        
        volunteers.each do |volunteer|
          score = 0.0
          
          # Base score from completed tasks
          completed_tasks = volunteer.task_assignments
                                    .completed
                                    .where(completed_at: period_start..Time.current)
          
          completed_tasks.each do |assignment|
            task_score = assignment.task_template&.xp_reward || 10
            difficulty_multiplier = assignment.task_template&.level_required || 1
            score += task_score * difficulty_multiplier * 0.1
          end
          
          # Bonus for activity multiplier
          score *= volunteer.activity_multiplier
          
          # Bonus for referral activity during period
          referral_bonus = calculate_referral_contribution(volunteer, period_start)
          score += referral_bonus
          
          # Penalty for late submissions or rejections
          penalty = calculate_performance_penalty(volunteer, period_start)
          score = [score - penalty, 0].max
          
          scores[volunteer] = score.round(2)
        end
        
        scores
      end

      def calculate_referral_contribution(volunteer, period_start)
        # Give bonus points for referrals who were active during period
        active_referrals = volunteer.referrals_made
                                   .joins(:referred)
                                   .joins(referred: :task_assignments)
                                   .where(
                                     decidim_volunteer_scheduler_task_assignments: {
                                       status: 'completed',
                                       completed_at: period_start..Time.current
                                     }
                                   )
                                   .distinct
                                   .count
        
        active_referrals * 5.0 # 5 points per active referral
      end

      def calculate_performance_penalty(volunteer, period_start)
        penalties = 0.0
        
        # Penalty for rejected tasks
        rejected_count = volunteer.task_assignments
                                  .rejected
                                  .where(updated_at: period_start..Time.current)
                                  .count
        penalties += rejected_count * 2.0
        
        # Penalty for overdue submissions
        overdue_count = volunteer.task_assignments
                                 .where(status: ['in_progress', 'submitted'])
                                 .where('assigned_at < ?', 7.days.ago)
                                 .count
        penalties += overdue_count * 1.0
        
        penalties
      end

      def distribute_daily_budget(ranked_volunteers)
        # Daily distribution: Top 5 performers get bonuses
        top_performers = ranked_volunteers.first(5)
        
        return if top_performers.empty?
        
        # Distribution: 50%, 25%, 15%, 7%, 3%
        distribution_percentages = [0.50, 0.25, 0.15, 0.07, 0.03]
        
        top_performers.each_with_index do |(volunteer, score), index|
          bonus_amount = (@pool_amount * distribution_percentages[index]).round(2)
          next if bonus_amount < 0.01
          
          create_bonus_transaction(volunteer, bonus_amount, "Daily performance bonus - Rank ##{index + 1}", score)
        end
      end

      def distribute_weekly_budget(ranked_volunteers)
        # Weekly distribution: Top 10 performers get bonuses
        top_performers = ranked_volunteers.first(10)
        
        return if top_performers.empty?
        
        total_score = top_performers.sum { |_, score| score }
        return if total_score <= 0
        
        top_performers.each_with_index do |(volunteer, score), index|
          # Proportional distribution based on performance score
          score_percentage = score / total_score
          bonus_amount = (@pool_amount * score_percentage).round(2)
          next if bonus_amount < 0.01
          
          create_bonus_transaction(volunteer, bonus_amount, "Weekly performance bonus - Rank ##{index + 1}", score)
        end
      end

      def distribute_monthly_budget(ranked_volunteers)
        # Monthly distribution: Top 25% of volunteers get bonuses
        total_volunteers = ranked_volunteers.length
        bonus_recipient_count = [total_volunteers / 4, 1].max
        
        top_performers = ranked_volunteers.first(bonus_recipient_count)
        return if top_performers.empty?
        
        total_score = top_performers.sum { |_, score| score }
        return if total_score <= 0
        
        top_performers.each_with_index do |(volunteer, score), index|
          # Weighted distribution with extra bonus for top 3
          base_percentage = score / total_score
          top_bonus = index < 3 ? 0.1 : 0.0
          
          final_percentage = [base_percentage + top_bonus, 0.5].min # Cap at 50%
          bonus_amount = (@pool_amount * final_percentage).round(2)
          next if bonus_amount < 0.01
          
          create_bonus_transaction(volunteer, bonus_amount, "Monthly performance bonus - Rank ##{index + 1}", score)
        end
      end

      def create_bonus_transaction(volunteer, amount, description, performance_score)
        transaction = volunteer.scicent_transactions.create!(
          transaction_type: 'performance_bonus',
          amount: amount,
          description: description,
          status: 'completed',
          metadata: {
            period_type: @period_type,
            performance_score: performance_score,
            distribution_date: Date.current
          }
        )
        
        Rails.logger.info "Awarded #{amount} tokens to #{volunteer.user.name} (score: #{performance_score})"
        
        # Send notification
        notify_bonus_recipient(volunteer, amount, description, performance_score)
        
        transaction
      end

      def notify_bonus_recipient(volunteer, amount, description, score)
        Decidim::EventsManager.publish(
          event: "decidim.volunteer_scheduler.performance_bonus_earned",
          event_class: Decidim::VolunteerScheduler::PerformanceBonusEvent,
          resource: volunteer,
          affected_users: [volunteer.user],
          extra: {
            bonus_amount: amount,
            period_type: @period_type,
            performance_score: score,
            description: description
          }
        )
      rescue NameError
        # Event system not available, skip notification
        Rails.logger.warn "Event system not available for performance bonus notification"
      end

      def period_start_date
        case @period_type
        when 'daily'
          Date.current.beginning_of_day
        when 'weekly'
          Date.current.beginning_of_week
        when 'monthly'
          Date.current.beginning_of_month
        end
      end

      def minimum_tasks_for_period
        case @period_type
        when 'daily'
          1
        when 'weekly'
          3
        when 'monthly'
          10
        end
      end
    end
  end
end