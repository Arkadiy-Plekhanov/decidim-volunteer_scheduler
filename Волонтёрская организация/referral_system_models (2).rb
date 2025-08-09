# app/models/decidim/volunteer_scheduler/referral.rb
module Decidim
  module VolunteerScheduler
    class Referral < ApplicationRecord
      self.table_name = "decidim_volunteer_scheduler_referrals"
      
      belongs_to :referrer, class_name: "Decidim::User"
      belongs_to :referred, class_name: "Decidim::User"
      
      has_many :scicent_transactions, as: :source, 
               class_name: "Decidim::VolunteerScheduler::ScicentTransaction"
      
      validates :level, inclusion: { in: 1..5 }
      validates :commission_rate, numericality: { 
        greater_than: 0, less_than_or_equal_to: 1 
      }
      validates :referrer_id, uniqueness: { scope: :referred_id }
      
      after_create :activate_referral
      
      # Commission rates decrease by level (10%, 8%, 6%, 4%, 2%)
      COMMISSION_RATES = {
        1 => 0.10, # 10% direct referral
        2 => 0.08, # 8% second level
        3 => 0.06, # 6% third level
        4 => 0.04, # 4% fourth level
        5 => 0.02  # 2% fifth level
      }.freeze
      
      scope :active, -> { where(active: true) }
      scope :by_level, ->(level) { where(level: level) }
      
      def self.create_referral_chain(referrer, referred)
        return if referrer == referred
        return if where(referred: referred).exists? # Prevent duplicate chains
        
        transaction do
          current_referrer = referrer
          level = 1
          
          while current_referrer && level <= 5
            # Avoid circular references
            break if current_referrer == referred
            
            referral = create!(
              referrer: current_referrer,
              referred: referred,
              level: level,
              commission_rate: COMMISSION_RATES[level],
              active: true,
              activation_date: Time.current
            )
            
            # Trigger activity multiplier recalculation for referrer
            RecalculateActivityMultiplierJob.perform_later(current_referrer.id)
            
            # Move up the chain
            current_referrer = current_referrer.volunteer_profile&.referrer
            level += 1
          end
          
          # Update referred user's profile to show referrer
          referred.volunteer_profile&.update(referrer: referrer) if referred.volunteer_profile
          
          # Trigger welcome event for new referral
          trigger_referral_created_event(referrer, referred)
        end
      end
      
      def add_commission(sale_amount)
        return 0 if !active? || sale_amount <= 0
        
        commission_amount = sale_amount * commission_rate
        
        transaction do
          # Update referral total
          increment(:total_commission, commission_amount)
          
          # Update referrer's profile
          referrer.volunteer_profile&.increment(:referral_scicent_earned, commission_amount)
          
          # Create transaction record
          ScicentTransaction.create!(
            user: referrer,
            source: self,
            transaction_type: :referral_commission,
            amount: commission_amount,
            status: :completed,
            description: "Commission from #{referred.name}'s sale (Level #{level})",
            processed_at: Time.current,
            metadata: {
              sale_amount: sale_amount,
              commission_rate: commission_rate,
              referral_level: level,
              referred_user_id: referred_id
            }
          )
          
          # Trigger commission earned event
          trigger_commission_earned_event(commission_amount, sale_amount)
        end
        
        commission_amount
      end
      
      def deactivate!
        transaction do
          update!(active: false)
          
          # Recalculate activity multipliers for affected users
          RecalculateActivityMultiplierJob.perform_later(referrer_id)
          RecalculateActivityMultiplierJob.perform_later(referred_id)
        end
      end
      
      def reactivate!
        return unless can_reactivate?
        
        transaction do
          update!(active: true, activation_date: Time.current)
          
          # Recalculate activity multipliers for affected users
          RecalculateActivityMultiplierJob.perform_later(referrer_id)
          RecalculateActivityMultiplierJob.perform_later(referred_id)
        end
      end
      
      def referred_is_active?
        return false unless referred.volunteer_profile
        
        # Consider active if they've had activity in the last 30 days
        referred.volunteer_profile.last_activity_at && 
        referred.volunteer_profile.last_activity_at > 30.days.ago
      end
      
      def activity_multiplier_contribution
        return 0 unless active? && referred_is_active?
        
        # Each active referral at each level contributes to multiplier
        case level
        when 1 then 0.15  # Direct referrals contribute more
        when 2 then 0.12
        when 3 then 0.09
        when 4 then 0.06
        when 5 then 0.03
        else 0
        end
      end
      
      private
      
      def activate_referral
        self.activation_date = Time.current if activation_date.blank?
      end
      
      def can_reactivate?
        # Add business logic for when referrals can be reactivated
        !active? && referred.volunteer_profile&.last_activity_at && 
        referred.volunteer_profile.last_activity_at > 7.days.ago
      end
      
      def self.trigger_referral_created_event(referrer, referred)
        Decidim::EventsManager.publish(
          event: "decidim.volunteer_scheduler.referral_created",
          event_class: "Decidim::VolunteerScheduler::ReferralCreatedEvent",
          resource: referrer.volunteer_profile,
          affected_users: [referrer],
          extra: {
            referred_user_name: referred.name,
            referral_code: referrer.volunteer_profile.referral_code
          }
        )
      end
      
      def trigger_commission_earned_event(commission_amount, sale_amount)
        Decidim::EventsManager.publish(
          event: "decidim.volunteer_scheduler.commission_earned",
          event_class: "Decidim::VolunteerScheduler::CommissionEarnedEvent",
          resource: self,
          affected_users: [referrer],
          extra: {
            commission_amount: commission_amount,
            sale_amount: sale_amount,
            referral_level: level,
            referred_user_name: referred.name
          }
        )
      end
    end
  end
end

# app/models/decidim/volunteer_scheduler/scicent_transaction.rb
module Decidim
  module VolunteerScheduler
    class ScicentTransaction < ApplicationRecord
      self.table_name = "decidim_volunteer_scheduler_scicent_transactions"
      
      belongs_to :user, class_name: "Decidim::User"
      belongs_to :source, polymorphic: true
      
      enum transaction_type: {
        task_reward: 0,
        referral_commission: 1,
        sale_commission: 2,
        admin_bonus: 3,
        team_bonus: 4,
        penalty: 5,
        adjustment: 6
      }
      
      enum status: { pending: 0, completed: 1, failed: 2, cancelled: 3 }
      
      validates :amount, numericality: { greater_than: 0 }
      validates :transaction_type, presence: true
      validates :description, presence: true
      
      scope :successful, -> { where(status: :completed) }
      scope :by_user, ->(user) { where(user: user) }
      scope :by_type, ->(type) { where(transaction_type: type) }
      scope :recent, -> { order(created_at: :desc) }
      
      before_create :set_processed_at_if_completed
      after_update :handle_status_change, if: :saved_change_to_status?
      
      def self.create_referral_commission_batch(user_id, sale_amount)
        user = Decidim::User.find(user_id)
        referrals = Referral.active.where(referred: user).includes(:referrer)
        
        total_distributed = 0
        
        transaction do
          referrals.each do |referral|
            commission = referral.add_commission(sale_amount)
            total_distributed += commission
          end
        end
        
        total_distributed
      end
      
      def self.monthly_summary(user, month = Date.current.beginning_of_month)
        where(user: user)
          .where(created_at: month..month.end_of_month)
          .successful
          .group(:transaction_type)
          .sum(:amount)
      end
      
      def self.total_earned(user)
        where(user: user).successful.sum(:amount)
      end
      
      def formatted_amount
        "#{amount} SCT"
      end
      
      private
      
      def set_processed_at_if_completed
        self.processed_at = Time.current if status == 'completed'
      end
      
      def handle_status_change
        case status
        when 'completed'
          self.processed_at = Time.current
          save! if changed?
        when 'failed', 'cancelled'
          # Handle failed/cancelled transaction logic if needed
          Rails.logger.warn "Transaction #{id} changed to #{status}: #{description}"
        end
      end
    end
  end
end
          