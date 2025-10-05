# frozen_string_literal: true

module Decidim
  module VolunteerScheduler
    # Background job for distributing referral commissions across the 5-level chain
    class CommissionDistributionJob < ApplicationJob
      queue_as :default

      # Process commission distribution for a Scicent token sale
      # @param sale_data [Hash] Sale information from webhook
      #   - user_id: ID of the user who made the sale
      #   - amount: Sale amount in tokens
      #   - transaction_id: External transaction reference
      def perform(sale_data)
        @sale_data = sale_data
        @buyer_profile = find_buyer_profile
        
        return unless @buyer_profile

        Rails.logger.info "Processing commission distribution for sale: #{@sale_data[:transaction_id]}"
        
        # Create the main sale transaction record
        create_sale_transaction
        
        # Distribute commissions up the referral chain
        distribute_commissions
        
        Rails.logger.info "Commission distribution completed for #{@sale_data[:transaction_id]}"
      rescue StandardError => e
        Rails.logger.error "Commission distribution failed: #{e.message}"
        Rails.logger.error e.backtrace.join("\n")
        raise e
      end

      private

      def find_buyer_profile
        user = Decidim::User.find_by(id: @sale_data[:user_id])
        return unless user

        # Ensure volunteer profile exists
        user.volunteer_profile || user.create_volunteer_profile!(
          organization: user.organization,
          referral_code: generate_referral_code
        )
      end

      def create_sale_transaction
        @sale_transaction = @buyer_profile.scicent_transactions.create!(
          transaction_type: 'token_purchase',
          amount: @sale_data[:amount],
          description: "Token purchase - Transaction ##{@sale_data[:transaction_id]}",
          external_transaction_id: @sale_data[:transaction_id],
          status: 'completed'
        )
      end

      def distribute_commissions
        current_profile = @buyer_profile
        commission_level = 1
        total_distributed = 0

        # Walk up the referral chain (max 5 levels)
        while current_profile.referrer && commission_level <= 5
          referrer_profile = current_profile.referrer
          commission_rate = commission_rates[commission_level]
          commission_amount = (@sale_data[:amount] * commission_rate).round(2)

          # Skip if commission amount is too small
          if commission_amount >= minimum_commission_amount
            create_commission_transaction(referrer_profile, commission_amount, commission_level)
            total_distributed += commission_amount
            
            Rails.logger.info "Distributed #{commission_amount} tokens to Level #{commission_level} referrer: #{referrer_profile.user.name}"
          end

          current_profile = referrer_profile
          commission_level += 1
        end

        Rails.logger.info "Total commission distributed: #{total_distributed} tokens across #{commission_level - 1} levels"
      end

      def create_commission_transaction(referrer_profile, amount, level)
        referrer_profile.scicent_transactions.create!(
          transaction_type: 'referral_commission',
          amount: amount,
          description: "Level #{level} referral commission from #{@buyer_profile.user.name}",
          external_transaction_id: @sale_data[:transaction_id],
          status: 'completed',
          metadata: {
            commission_level: level,
            original_sale_amount: @sale_data[:amount],
            buyer_id: @buyer_profile.user.id,
            commission_rate: commission_rates[level]
          }
        )

        # Update referrer's activity multiplier
        referrer_profile.calculate_activity_multiplier!

        # Send notification to referrer
        notify_referrer(referrer_profile, amount, level)
      end

      def commission_rates
        @commission_rates ||= {
          1 => 0.10, # 10%
          2 => 0.08, # 8%
          3 => 0.06, # 6%
          4 => 0.04, # 4%
          5 => 0.02  # 2%
        }
      end

      def minimum_commission_amount
        0.01 # Minimum 0.01 tokens to avoid micro-transactions
      end

      def notify_referrer(referrer_profile, amount, level)
        Decidim::EventsManager.publish(
          event: "decidim.volunteer_scheduler.referral_commission_earned",
          event_class: Decidim::VolunteerScheduler::ReferralCommissionEvent,
          resource: @sale_transaction,
          affected_users: [referrer_profile.user],
          extra: {
            commission_amount: amount,
            commission_level: level,
            buyer_name: @buyer_profile.user.name,
            original_sale_amount: @sale_data[:amount]
          }
        )
      rescue NameError
        # Event system not available, skip notification
        Rails.logger.warn "Event system not available for referral commission notification"
      end

      def generate_referral_code
        loop do
          code = SecureRandom.alphanumeric(8).upcase
          break code unless Decidim::VolunteerScheduler::VolunteerProfile.exists?(referral_code: code)
        end
      end
    end
  end
end