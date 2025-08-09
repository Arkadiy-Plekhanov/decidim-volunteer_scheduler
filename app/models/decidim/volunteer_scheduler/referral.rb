# frozen_string_literal: true

module Decidim
  module VolunteerScheduler
    # Model representing a referral relationship between volunteers
    class Referral < ApplicationRecord
      include Decidim::Traceable
      include Decidim::Loggable

      belongs_to :referrer, class_name: "Decidim::VolunteerScheduler::VolunteerProfile"
      belongs_to :referred, class_name: "Decidim::VolunteerScheduler::VolunteerProfile"

      validates :level, presence: true, inclusion: { in: 1..5 }
      validates :commission_rate, presence: true, numericality: { greater_than: 0, less_than: 1 }
      validates :referrer_id, uniqueness: { scope: :referred_id }

      validate :prevent_self_referral
      validate :prevent_circular_referral

      scope :by_level, ->(level) { where(level: level) }
      scope :active, -> { joins(:referred).where("decidim_volunteer_scheduler_volunteer_profiles.last_activity_at > ?", 30.days.ago) }

      after_create :update_activity_multipliers

      def self.create_referral_chain(referrer_profile, referred_profile)
        return if referrer_profile == referred_profile
        
        transaction do
          # Create direct referral (level 1)
          create!(
            referrer: referrer_profile,
            referred: referred_profile,
            level: 1,
            commission_rate: get_commission_rate(1, referrer_profile.component)
          )
          
          # Create chain referrals up to level 5
          current_referrer = referrer_profile
          (2..5).each do |level|
            break unless current_referrer.referrer
            
            create!(
              referrer: current_referrer.referrer,
              referred: referred_profile,
              level: level,
              commission_rate: get_commission_rate(level, referrer_profile.component)
            )
            
            current_referrer = current_referrer.referrer
          end
        end
      end

      def self.get_commission_rate(level, component = nil)
        # Use component settings if available, otherwise use default rates
        default_rates = { 1 => 0.10, 2 => 0.08, 3 => 0.06, 4 => 0.04, 5 => 0.02 }
        
        if component&.settings
          case level
          when 1 then component.settings.referral_commission_l1 || default_rates[1]
          when 2 then component.settings.referral_commission_l2 || default_rates[2]
          when 3 then component.settings.referral_commission_l3 || default_rates[3]
          when 4 then component.settings.referral_commission_l4 || default_rates[4]
          when 5 then component.settings.referral_commission_l5 || default_rates[5]
          else 0.0
          end
        else
          default_rates[level] || 0.0
        end
      end

      def calculate_commission(sale_amount)
        (sale_amount * commission_rate).round(2)
      end

      def is_active?
        referred.last_activity_at && referred.last_activity_at > 30.days.ago
      end

      private

      def prevent_self_referral
        errors.add(:referred, "cannot refer themselves") if referrer_id == referred_id
      end

      def prevent_circular_referral
        return unless referrer && referred
        
        # Check if the referrer is already referred by the referred (circular reference)
        if Referral.exists?(referrer: referred, referred: referrer)
          errors.add(:base, "Circular referral not allowed")
        end
      end

      def update_activity_multipliers
        # Update activity multipliers for the referrer chain
        Decidim::VolunteerScheduler::ActivityMultiplierJob.perform_later(referrer.id)
      end
    end
  end
end
