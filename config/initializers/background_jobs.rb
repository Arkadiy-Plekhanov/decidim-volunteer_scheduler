# frozen_string_literal: true

# Background job configuration for Decidim Volunteer Scheduler
module Decidim
  module VolunteerScheduler
    # Configuration for background job queues and scheduling
    module BackgroundJobs
      # Job queue names (only define if not already defined to prevent reinitialization warnings)
      COMMISSION_QUEUE = 'volunteer_scheduler_commissions' unless defined?(COMMISSION_QUEUE)
      MULTIPLIER_QUEUE = 'volunteer_scheduler_multipliers' unless defined?(MULTIPLIER_QUEUE)
      BUDGET_QUEUE = 'volunteer_scheduler_budgets' unless defined?(BUDGET_QUEUE)

      # Scheduling configuration
      class << self
        def schedule_periodic_jobs
          # Schedule daily activity multiplier calculation
          # This should be run by a cron job or scheduler like whenever gem
          
          # Example cron schedule:
          # 0 2 * * * - Run daily at 2 AM
          # ActivityMultiplierCalculationJob.perform_later
          
          # Example for budget distribution:
          # Daily: 0 23 * * * - Run at 11 PM daily
          # Weekly: 0 0 * * 0 - Run at midnight on Sunday
          # Monthly: 0 0 1 * * - Run at midnight on the 1st of each month
        end
        
        def configure_sidekiq_cron
          # Configuration for sidekiq-cron gem if used
          # This would typically be configured in config/initializers/sidekiq.rb
          return unless defined?(Sidekiq::Cron::Job)
          
          # Daily activity multiplier calculation
          Sidekiq::Cron::Job.create(
            name: 'Daily Activity Multiplier Calculation',
            cron: '0 2 * * *', # 2 AM daily
            class: 'Decidim::VolunteerScheduler::ActivityMultiplierCalculationJob'
          )
          
          # Weekly budget distribution
          Sidekiq::Cron::Job.create(
            name: 'Weekly Budget Distribution',
            cron: '0 0 * * 0', # Midnight Sunday
            class: 'Decidim::VolunteerScheduler::BudgetDistributionJob',
            args: ['weekly', nil, 1000.0] # Example: 1000 tokens per week
          )
          
          # Monthly budget distribution
          Sidekiq::Cron::Job.create(
            name: 'Monthly Budget Distribution',
            cron: '0 0 1 * *', # Midnight 1st of month
            class: 'Decidim::VolunteerScheduler::BudgetDistributionJob',
            args: ['monthly', nil, 5000.0] # Example: 5000 tokens per month
          )
        rescue StandardError => e
          Rails.logger.warn "Failed to configure Sidekiq cron jobs: #{e.message}"
        end
        
        def test_commission_calculation(user_id, amount, transaction_id)
          # Test method for commission distribution
          sale_data = {
            user_id: user_id,
            amount: amount,
            transaction_id: transaction_id
          }
          
          CommissionDistributionJob.perform_later(sale_data)
          Rails.logger.info "Test commission distribution queued for user #{user_id}"
        end
      end
    end
  end
end

# Configure background jobs on Rails initialization
Rails.application.config.after_initialize do
  # Configure Sidekiq queues if Sidekiq is available
  if defined?(Sidekiq)
    # Set queue priorities and weights
    # Higher weight = higher priority
    sidekiq_queues = {
      'default' => 5,
      Decidim::VolunteerScheduler::BackgroundJobs::COMMISSION_QUEUE => 10,
      Decidim::VolunteerScheduler::BackgroundJobs::MULTIPLIER_QUEUE => 3,
      Decidim::VolunteerScheduler::BackgroundJobs::BUDGET_QUEUE => 2
    }
    
    # Configure Sidekiq cron jobs if available
    Decidim::VolunteerScheduler::BackgroundJobs.configure_sidekiq_cron
  end
end