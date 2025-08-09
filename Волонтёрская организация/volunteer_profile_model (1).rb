# app/models/decidim/volunteer_scheduler/volunteer_profile.rb
module Decidim
  module VolunteerScheduler
    class VolunteerProfile < ApplicationRecord
      self.table_name = "decidim_volunteer_scheduler_volunteer_profiles"
      
      belongs_to :user, class_name: "Decidim::User"
      belongs_to :referrer, class_name: "Decidim::User", optional: true
      
      has_many :task_assignments, foreign_key: :assignee_id, primary_key: :user_id,
               class_name: "Decidim::VolunteerScheduler::TaskAssignment"
      has_many :team_memberships, foreign_key: :user_id, primary_key: :user_id,
               class_name: "Decidim::VolunteerScheduler::TeamMembership"
      has_many :teams, through: :team_memberships
      has_many :referrals_made, class_name: "Decidim::VolunteerScheduler::Referral", 
               foreign_key: :referrer_id, primary_key: :user_id
      has_many :referrals_received, class_name: "Decidim::VolunteerScheduler::Referral",
               foreign_key: :referred_id, primary_key: :user_id
      has_many :scicent_transactions, foreign_key: :user_id, primary_key: :user_id,
               class_name: "Decidim::VolunteerScheduler::ScicentTransaction"
      
      validates :referral_code, presence: true, uniqueness: true
      validates :level, inclusion: { in: 1..3 }
      validates :activity_multiplier, numericality: { greater_than: 0, less_than_or_equal_to: 3.0 }
      
      before_validation :generate_referral_code, on: :create
      after_create :initialize_capabilities
      
      # XP and Level Management
      LEVEL_THRESHOLDS = { 1 => 0, 2 => 100, 3 => 500 }.freeze
      LEVEL_CAPABILITIES = {
        1 => %w[basic_tasks],
        2 => %w[basic_tasks team_creation mentoring intermediate_tasks],
        3 => %w[basic_tasks team_creation mentoring intermediate_tasks 
                advanced_tasks team_leadership admin_tasks]
      }.freeze
      
      def add_xp(amount)
        return if amount <= 0
        
        old_level = level
        self.total_xp += amount
        new_level = calculate_level_from_xp
        
        if new_level > old_level
          level_up_to(new_level)
          trigger_level_up_event(old_level, new_level)
        end
        
        update_last_activity
        save!
      end
      
      def add_scicent(amount, source = nil)
        return if amount <= 0
        
        self.total_scicent_earned += amount
        update_last_activity
        save!
        
        # Create transaction record
        ScicentTransaction.create!(
          user: user,
          source: source,
          transaction_type: :task_reward,
          amount: amount,
          status: :completed,
          description: "Scicent reward earned",
          processed_at: Time.current
        )
      end
      
      def increment_tasks_completed
        self.tasks_completed += 1
        update_last_activity
        save!
      end
      
      def level_up_if_needed!
        new_level = calculate_level_from_xp
        if new_level > level
          old_level = level
          level_up_to(new_level)
          trigger_level_up_event(old_level, new_level)
          save!
        end
      end
      
      def can_access_capability?(capability)
        current_capabilities.include?(capability.to_s)
      end
      
      def current_capabilities
        LEVEL_CAPABILITIES[level] || []
      end
      
      def progress_to_next_level
        return 100 if level >= 3
        
        current_threshold = LEVEL_THRESHOLDS[level]
        next_threshold = LEVEL_THRESHOLDS[level + 1]
        
        return 100 if next_threshold.nil?
        
        progress = ((total_xp - current_threshold).to_f / (next_threshold - current_threshold)) * 100
        [progress, 100].min.round(2)
      end
      
      def xp_to_next_level
        return 0 if level >= 3
        
        next_threshold = LEVEL_THRESHOLDS[level + 1]
        [next_threshold - total_xp, 0].max
      end
      
      def referral_link
        return nil unless referral_code.present?
        
        Rails.application.routes.url_helpers.new_user_registration_url(
          host: user.organization.host,
          ref: referral_code
        )
      end
      
      def active_referrals_count
        referrals_made.joins(:referred)
                     .merge(User.joins(:volunteer_profile)
                               .where("decidim_volunteer_scheduler_volunteer_profiles.last_activity_at > ?", 1.month.ago))
                     .count
      end
      
      def total_referral_commission
        referrals_made.sum(:total_commission)
      end
      
      def calculate_activity_multiplier
        base_multiplier = 1.0
        
        # Level bonus (0.1 per level above 1)
        level_bonus = (level - 1) * 0.1
        
        # Activity bonus (based on recent completions)
        activity_bonus = calculate_activity_bonus
        
        # Referral bonus (based on active referrals)
        referral_bonus = calculate_referral_bonus
        
        # Team leadership bonus
        leadership_bonus = calculate_leadership_bonus
        
        new_multiplier = [base_multiplier + level_bonus + activity_bonus + referral_bonus + leadership_bonus, 3.0].min
        
        if activity_multiplier != new_multiplier
          update_column(:activity_multiplier, new_multiplier)
        end
        
        new_multiplier
      end
      
      private
      
      def generate_referral_code
        loop do
          code = SecureRandom.alphanumeric(8).upcase
          if self.class.where(referral_code: code).empty?
            self.referral_code = code
            break
          end
        end
      end
      
      def initialize_capabilities
        self.capabilities = { "basic_tasks" => true }
        save!
      end
      
      def calculate_level_from_xp
        LEVEL_THRESHOLDS.select { |level, threshold| total_xp >= threshold }.keys.max
      end
      
      def level_up_to(new_level)
        self.level = new_level
        unlock_capabilities(new_level)
        add_level_up_achievement(new_level)
      end
      
      def unlock_capabilities(new_level)
        new_caps = LEVEL_CAPABILITIES[new_level] || []
        current_caps = capabilities || {}
        
        new_caps.each do |capability|
          current_caps[capability] = true
        end
        
        self.capabilities = current_caps
      end
      
      def add_level_up_achievement(new_level)
        current_achievements = achievements || []
        current_achievements << {
          type: 'level_up',
          level: new_level,
          earned_at: Time.current.iso8601,
          xp_at_time: total_xp
        }
        self.achievements = current_achievements
      end
      
      def trigger_level_up_event(old_level, new_level)
        Decidim::EventsManager.publish(
          event: "decidim.volunteer_scheduler.level_up",
          event_class: "Decidim::VolunteerScheduler::LevelUpEvent",
          resource: self,
          affected_users: [user],
          extra: {
            old_level: old_level,
            new_level: new_level,
            new_capabilities: LEVEL_CAPABILITIES[new_level] - LEVEL_CAPABILITIES[old_level]
          }
        )
      end
      
      def update_last_activity
        self.last_activity_at = Time.current
      end
      
      def calculate_activity_bonus
        recent_completions = task_assignments.where(status: :completed)
                                           .where("completed_at > ?", 1.month.ago)
                                           .count
        
        # 5% bonus per 10 completed tasks in the last month
        (recent_completions / 10.0) * 0.05
      end
      
      def calculate_referral_bonus
        active_count = active_referrals_count
        
        # 10% bonus per 5 active referrals
        (active_count / 5.0) * 0.1
      end
      
      def calculate_leadership_bonus
        return 0 unless can_access_capability?("team_leadership")
        
        teams_led = teams.where(leader_id: user_id).count
        active_team_members = TeamMembership.joins(:team)
                                          .where(decidim_volunteer_scheduler_teams: { leader_id: user_id })
                                          .where(active: true)
                                          .count
        
        # Bonus based on team size and activity
        team_bonus = teams_led * 0.05
        member_bonus = (active_team_members / 10.0) * 0.05
        
        team_bonus + member_bonus
      end
    end
  end
end