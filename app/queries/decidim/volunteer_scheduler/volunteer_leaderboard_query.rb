# frozen_string_literal: true

module Decidim
  module VolunteerScheduler
    # Query object to retrieve volunteer leaderboard data
    class VolunteerLeaderboardQuery
      def initialize(organization:, component: nil, time_range: :monthly)
        @organization = organization
        @component = component
        @time_range = time_range
      end

      def call
        scope = base_scope
        scope = filter_by_component(scope) if component
        scope = filter_by_time_range(scope)
        scope = add_calculated_fields(scope)
        
        scope.order(period_xp: :desc, total_xp: :desc)
             .limit(100)
      end

      def top_performers(limit = 10)
        call.limit(limit)
      end

      def volunteer_rank(volunteer_profile)
        subquery = base_scope
        subquery = filter_by_component(subquery) if component
        subquery = filter_by_time_range(subquery)
        
        rank = subquery.where("total_xp > ?", volunteer_profile.total_xp).count + 1
        
        {
          rank: rank,
          total_volunteers: subquery.count,
          percentile: calculate_percentile(rank, subquery.count)
        }
      end

      private

      attr_reader :organization, :component, :time_range

      def base_scope
        VolunteerProfile
          .joins(:user)
          .where(organization: organization)
          .where(users: { deleted_at: nil, blocked_at: nil })
      end

      def filter_by_component(scope)
        scope.where(component: component)
      end

      def filter_by_time_range(scope)
        case time_range
        when :daily
          scope.joins(:task_assignments)
               .where(task_assignments: { 
                 status: :approved,
                 reviewed_at: 1.day.ago..Time.current 
               })
               .group("decidim_volunteer_scheduler_volunteer_profiles.id")
        when :weekly
          scope.joins(:task_assignments)
               .where(task_assignments: { 
                 status: :approved,
                 reviewed_at: 1.week.ago..Time.current 
               })
               .group("decidim_volunteer_scheduler_volunteer_profiles.id")
        when :monthly
          scope.joins(:task_assignments)
               .where(task_assignments: { 
                 status: :approved,
                 reviewed_at: 1.month.ago..Time.current 
               })
               .group("decidim_volunteer_scheduler_volunteer_profiles.id")
        else
          scope
        end
      end

      def add_calculated_fields(scope)
        scope.select(
          "decidim_volunteer_scheduler_volunteer_profiles.*",
          "decidim_users.name as user_name",
          "decidim_users.nickname as user_nickname",
          "COUNT(DISTINCT decidim_volunteer_scheduler_task_assignments.id) as tasks_completed",
          "COALESCE(SUM(
            CASE 
              WHEN decidim_volunteer_scheduler_task_assignments.reviewed_at >= '#{time_range_start}'
              THEN decidim_volunteer_scheduler_task_templates.xp_reward * decidim_volunteer_scheduler_volunteer_profiles.activity_multiplier
              ELSE 0
            END
          ), 0) as period_xp"
        ).joins(
          task_assignments: :task_template
        )
      end

      def time_range_start
        case time_range
        when :daily
          1.day.ago
        when :weekly
          1.week.ago
        when :monthly
          1.month.ago
        else
          Time.at(0)
        end
      end

      def calculate_percentile(rank, total)
        return 100 if total == 0
        ((total - rank + 1).to_f / total * 100).round(2)
      end
    end
  end
end