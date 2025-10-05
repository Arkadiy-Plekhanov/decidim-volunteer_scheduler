# frozen_string_literal: true

module Decidim
  module VolunteerScheduler
    module ContentBlocks
      class VolunteerDashboardCell < Decidim::ViewModel
        def show
          # Always show content block - template will handle different states
          render
        end

        private

        def current_volunteer_profile
          @current_volunteer_profile ||= current_user&.volunteer_profile
        end

        def available_tasks
          @available_tasks ||= Decidim::VolunteerScheduler::TaskTemplate
                              .includes(:organization)
                              .where(organization: current_organization)
                              .published
                              .where("level_required <= ?", current_volunteer_profile&.level || 1)
                              .limit(5)
        end

        def my_assignments
          @my_assignments ||= current_volunteer_profile&.task_assignments
                             &.includes(:task_template, :organization)
                             &.order(assigned_at: :desc)
                             &.limit(5) || []
        end

        def recent_transactions
          @recent_transactions ||= current_volunteer_profile&.scicent_transactions
                                  &.order(created_at: :desc)
                                  &.limit(5) || []
        end

        def referral_stats
          return {} unless current_volunteer_profile

          {
            total_referrals: current_volunteer_profile.total_referrals_count,
            active_referrals: current_volunteer_profile.active_referrals_count,
            total_commission: current_volunteer_profile.scicent_transactions
                                                     .where(transaction_type: 'referral_commission')
                                                     .sum(:amount),
            this_month_earnings: current_volunteer_profile.scicent_transactions
                                                          .where(created_at: Time.current.beginning_of_month..Time.current.end_of_month)
                                                          .sum(:amount),
            referral_code: current_volunteer_profile.referral_code
          }
        end

        def volunteer_stats
          return {} unless current_volunteer_profile
          
          {
            level: current_volunteer_profile.level,
            total_xp: current_volunteer_profile.total_xp,
            xp_to_next_level: current_volunteer_profile.next_level_xp,
            activity_multiplier: current_volunteer_profile.activity_multiplier,
            total_tasks_completed: current_volunteer_profile.task_assignments.approved.count,
            rank_in_organization: calculate_rank_in_organization
          }
        end

        def recent_achievements
          return [] unless current_volunteer_profile
          
          achievements = []
          
          # Recent level ups (check transaction history)
          level_up_transactions = current_volunteer_profile.scicent_transactions
                                                          .where(transaction_type: 'level_bonus')
                                                          .where('created_at > ?', 30.days.ago)
                                                          .order(created_at: :desc)
                                                          .limit(3)
          
          achievements += level_up_transactions.map do |transaction|
            {
              type: 'level_up',
              title: "Level Up Achievement!",
              description: "Reached Level #{current_volunteer_profile.level}",
              date: transaction.created_at,
              icon: 'trophy-line'
            }
          end
          
          # Recent approved tasks
          recent_completed = current_volunteer_profile.task_assignments
                                                    .approved
                                                    .includes(:task_template)
                                                    .where('reviewed_at > ?', 7.days.ago)
                                                    .order(reviewed_at: :desc)
                                                    .limit(3)
          
          achievements += recent_completed.map do |assignment|
            {
              type: 'task_completed',
              title: "Task Completed",
              description: assignment.task_template.title,
              date: assignment.reviewed_at,
              icon: 'check-line'
            }
          end
          
          achievements.sort_by { |a| a[:date] }.reverse.first(5)
        end

        private

        def calculate_rank_in_organization
          return nil unless current_volunteer_profile
          
          # Count volunteers with higher XP
          higher_xp_count = Decidim::VolunteerScheduler::VolunteerProfile
                           .joins(:user)
                           .where(decidim_users: { organization: current_organization })
                           .where('decidim_volunteer_scheduler_volunteer_profiles.total_xp > ?', current_volunteer_profile.total_xp)
                           .count
          
          higher_xp_count + 1
        end
      end
    end
  end
end