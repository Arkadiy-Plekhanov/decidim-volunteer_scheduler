# frozen_string_literal: true

module Decidim
  module VolunteerScheduler
    # Service for processing referral commissions up the chain
    class ReferralProcessor
      def initialize(volunteer_profile, base_amount)
        @volunteer_profile = volunteer_profile
        @base_amount = base_amount
      end

      def call
        return unless @volunteer_profile.referrer
        
        process_referral_chain
      end

      private

      def process_referral_chain
        referrals = Referral.where(referred: @volunteer_profile)
                           .includes(:referrer)
                           .order(:level)
        
        referrals.each do |referral|
          commission_amount = calculate_commission(referral)
          next if commission_amount <= 0
          
          create_commission_transaction(referral, commission_amount)
          update_referrer_activity(referral.referrer)
        end
      end

      def calculate_commission(referral)
        commission = @base_amount * referral.commission_rate
        
        # Apply activity multiplier if referrer is active
        if referral.is_active?
          commission *= referral.referrer.activity_multiplier
        end
        
        commission.round(2)
      end

      def create_commission_transaction(referral, amount)
        ScicentTransaction.create_referral_commission!(
          referral.referrer,
          amount,
          @volunteer_profile.user.name,
          referral.level
        )
      end

      def update_referrer_activity(referrer)
        referrer.update(last_activity_at: Time.current)
        referrer.calculate_activity_multiplier!
      end
    end
  end
end
