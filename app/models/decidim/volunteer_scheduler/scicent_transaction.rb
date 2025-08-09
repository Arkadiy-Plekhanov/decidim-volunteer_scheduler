# frozen_string_literal: true

module Decidim
  module VolunteerScheduler
    # Model representing a Scicent token transaction for tracking rewards and commissions
    class ScicentTransaction < ApplicationRecord
      include Decidim::Traceable
      include Decidim::Loggable

      belongs_to :volunteer_profile, class_name: "Decidim::VolunteerScheduler::VolunteerProfile"

      validates :transaction_type, presence: true
      validates :amount, presence: true, numericality: true
      validates :description, presence: true

      enum transaction_type: {
        task_completion: 0,
        referral_commission: 1,
        level_bonus: 2,
        activity_multiplier: 3,
        monthly_distribution: 4,
        manual_adjustment: 5
      }

      scope :earnings, -> { where("amount > 0") }
      scope :deductions, -> { where("amount < 0") }
      scope :recent, -> { where("created_at > ?", 30.days.ago) }
      scope :by_type, ->(type) { where(transaction_type: type) }

      def self.total_balance_for(volunteer_profile)
        where(volunteer_profile: volunteer_profile).sum(:amount)
      end

      def self.monthly_earnings_for(volunteer_profile, month = Date.current.beginning_of_month)
        where(volunteer_profile: volunteer_profile)
          .where(created_at: month..month.end_of_month)
          .earnings
          .sum(:amount)
      end

      def self.create_task_completion!(volunteer_profile, xp_amount, task_title)
        create!(
          volunteer_profile: volunteer_profile,
          transaction_type: :task_completion,
          amount: xp_amount,
          xp_amount: xp_amount,
          description: "Task completed: #{task_title}"
        )
      end

      def self.create_referral_commission!(volunteer_profile, commission_amount, referred_name, level)
        create!(
          volunteer_profile: volunteer_profile,
          transaction_type: :referral_commission,
          amount: commission_amount,
          commission_amount: commission_amount,
          description: "Level #{level} referral commission from #{referred_name}"
        )
      end

      def self.create_level_bonus!(volunteer_profile, bonus_amount, new_level)
        create!(
          volunteer_profile: volunteer_profile,
          transaction_type: :level_bonus,
          amount: bonus_amount,
          description: "Level #{new_level} achievement bonus"
        )
      end

      def is_earning?
        amount > 0
      end

      def is_deduction?
        amount < 0
      end

      def formatted_amount
        if amount >= 0
          "+#{amount}"
        else
          amount.to_s
        end
      end
    end
  end
end
