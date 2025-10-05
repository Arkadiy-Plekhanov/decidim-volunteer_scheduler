# frozen_string_literal: true

module Decidim
  module VolunteerScheduler
    # Service class for calculating referral commissions and validating transactions
    class CommissionCalculator
      include ActiveModel::Model
      
      attr_accessor :buyer_profile, :sale_amount, :transaction_id

      def initialize(buyer_profile:, sale_amount:, transaction_id:)
        @buyer_profile = buyer_profile
        @sale_amount = sale_amount.to_f
        @transaction_id = transaction_id
        @commission_chain = []
      end

      # Calculate the full commission distribution chain
      # @return [Array<Hash>] Array of commission calculations
      def calculate_distribution
        validate_inputs!
        
        current_profile = buyer_profile
        level = 1
        total_commission = 0.0

        # Walk up the referral chain (max 5 levels)
        while current_profile.referrer && level <= 5
          referrer_profile = current_profile.referrer
          commission_data = calculate_level_commission(referrer_profile, level)
          
          if commission_data[:amount] >= minimum_commission
            @commission_chain << commission_data
            total_commission += commission_data[:amount]
          end

          current_profile = referrer_profile
          level += 1
        end

        {
          total_commission: total_commission,
          commission_chain: @commission_chain,
          levels_processed: level - 1,
          original_sale: {
            amount: sale_amount,
            buyer_id: buyer_profile.user.id,
            transaction_id: transaction_id
          }
        }
      end

      # Validate that commissions can be distributed
      # @return [Boolean] true if distribution is valid
      def valid_for_distribution?
        return false unless buyer_profile&.user&.confirmed?
        return false if sale_amount <= 0
        return false if transaction_id.blank?
        
        # Check for duplicate transactions
        return false if duplicate_transaction_exists?
        
        # Verify buyer profile integrity
        return false unless buyer_profile_valid?
        
        true
      end

      # Get commission rates for all levels
      # @return [Hash] Commission rates by level
      def commission_rates
        {
          1 => 0.10, # 10%
          2 => 0.08, # 8%
          3 => 0.06, # 6%
          4 => 0.04, # 4%
          5 => 0.02  # 2%
        }
      end

      # Calculate total possible commission if all 5 levels exist
      # @return [Float] Maximum possible commission
      def maximum_possible_commission
        commission_rates.values.sum * sale_amount
      end

      # Get statistics about the referral chain
      # @return [Hash] Chain statistics
      def chain_statistics
        referral_chain = []
        current_profile = buyer_profile
        
        while current_profile.referrer
          referral_chain << {
            level: referral_chain.length + 1,
            referrer_id: current_profile.referrer.id,
            referrer_name: current_profile.referrer.user.name,
            referrer_level: current_profile.referrer.level,
            referrer_activity_multiplier: current_profile.referrer.activity_multiplier,
            commission_rate: commission_rates[referral_chain.length + 1]
          }
          
          current_profile = current_profile.referrer
          break if referral_chain.length >= 5
        end

        {
          chain_depth: referral_chain.length,
          referrers: referral_chain,
          has_full_chain: referral_chain.length == 5
        }
      end

      private

      def validate_inputs!
        raise ArgumentError, "Buyer profile is required" unless buyer_profile
        raise ArgumentError, "Sale amount must be positive" unless sale_amount > 0
        raise ArgumentError, "Transaction ID is required" if transaction_id.blank?
        raise ArgumentError, "Invalid buyer profile" unless buyer_profile_valid?
      end

      def buyer_profile_valid?
        buyer_profile.is_a?(Decidim::VolunteerScheduler::VolunteerProfile) &&
          buyer_profile.persisted? &&
          buyer_profile.user&.confirmed?
      end

      def calculate_level_commission(referrer_profile, level)
        rate = commission_rates[level]
        amount = (sale_amount * rate).round(2)

        {
          referrer_profile: referrer_profile,
          referrer_id: referrer_profile.user.id,
          referrer_name: referrer_profile.user.name,
          level: level,
          rate: rate,
          amount: amount,
          description: "Level #{level} referral commission from #{buyer_profile.user.name}",
          metadata: {
            original_sale_amount: sale_amount,
            buyer_id: buyer_profile.user.id,
            transaction_id: transaction_id,
            calculation_timestamp: Time.current.iso8601
          }
        }
      end

      def minimum_commission
        0.01 # Minimum 1 cent to avoid micro-transactions
      end

      def duplicate_transaction_exists?
        Decidim::VolunteerScheduler::ScicentTransaction.exists?(
          external_transaction_id: transaction_id,
          transaction_type: ['token_purchase', 'referral_commission']
        )
      end

      # Anti-fraud checks
      def potential_fraud_indicators
        indicators = []
        
        # Check for rapid repeated transactions
        recent_transactions = buyer_profile.scicent_transactions
                                          .where('created_at > ?', 1.hour.ago)
                                          .where(transaction_type: 'token_purchase')
                                          .count

        indicators << "Rapid transaction frequency" if recent_transactions > 10

        # Check for unusually large amounts
        average_sale = Decidim::VolunteerScheduler::ScicentTransaction
                      .where(transaction_type: 'token_purchase')
                      .where('created_at > ?', 30.days.ago)
                      .average(:amount) || 100.0

        indicators << "Unusually large amount" if sale_amount > (average_sale * 10)

        # Check referral chain integrity
        indicators << "Suspicious referral chain" if referral_chain_suspicious?

        indicators
      end

      def referral_chain_suspicious?
        # Check for circular references or rapid chain creation
        current_profile = buyer_profile
        seen_profiles = Set.new
        rapid_creation_count = 0

        while current_profile.referrer
          # Check for circular reference
          return true if seen_profiles.include?(current_profile.id)
          seen_profiles.add(current_profile.id)

          # Check for rapid profile creation (potential fake referrals)
          if current_profile.created_at > 24.hours.ago
            rapid_creation_count += 1
          end

          current_profile = current_profile.referrer
          break if seen_profiles.size >= 10 # Safety break
        end

        # Flag if more than 2 profiles in chain were created in last 24h
        rapid_creation_count > 2
      end
    end
  end
end