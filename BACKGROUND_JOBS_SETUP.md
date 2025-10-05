# Background Jobs Setup - Decidim Volunteer Scheduler

This document explains how to configure and use the background job system for commission distribution, activity multiplier calculations, and budget allocations.

## Overview

The volunteer scheduler module uses background jobs for:

1. **Commission Distribution**: Automatically distribute referral commissions when token sales occur
2. **Activity Multiplier Calculation**: Daily calculation of activity multipliers with rolling windows
3. **Budget Distribution**: Daily/weekly/monthly budget allocation to top performers

## Job Classes

### CommissionDistributionJob
- **Purpose**: Process referral commissions for token sales
- **Trigger**: Webhook from Scicent token sales API
- **Queue**: `volunteer_scheduler_commissions` (high priority)

### ActivityMultiplierCalculationJob  
- **Purpose**: Recalculate activity multipliers for all volunteers
- **Schedule**: Daily at 2 AM
- **Queue**: `volunteer_scheduler_multipliers`

### BudgetDistributionJob
- **Purpose**: Distribute budget pools to top performers
- **Schedule**: Daily/weekly/monthly as configured
- **Queue**: `volunteer_scheduler_budgets`

## Setup Instructions

### 1. Install Background Job Processor

#### Option A: Sidekiq (Recommended)

Add to your Gemfile:
```ruby
gem 'sidekiq'
gem 'sidekiq-cron' # For scheduled jobs
```

Run: `bundle install`

Create `config/initializers/sidekiq.rb`:
```ruby
Sidekiq.configure_server do |config|
  config.redis = { url: ENV['REDIS_URL'] || 'redis://localhost:6379/0' }
  
  # Configure queues with priorities
  config.queues = [
    ['volunteer_scheduler_commissions', 10],
    ['default', 5],
    ['volunteer_scheduler_multipliers', 3], 
    ['volunteer_scheduler_budgets', 2]
  ]
end

Sidekiq.configure_client do |config|
  config.redis = { url: ENV['REDIS_URL'] || 'redis://localhost:6379/0' }
end
```

#### Option B: Delayed Job

Add to your Gemfile:
```ruby
gem 'delayed_job_active_record'
```

Run: 
```bash
bundle install
rails generate delayed_job:active_record
rails db:migrate
```

### 2. Configure Scheduled Jobs

#### With Sidekiq-Cron

The module automatically configures cron jobs if sidekiq-cron is available. Default schedule:
- Activity multipliers: Daily at 2 AM
- Weekly budget: Sundays at midnight  
- Monthly budget: 1st of month at midnight

#### With Whenever Gem

Add to your Gemfile:
```ruby
gem 'whenever', require: false
```

Create `config/schedule.rb`:
```ruby
# Daily activity multiplier calculation
every 1.day, at: '2:00 am' do
  runner "Decidim::VolunteerScheduler::ActivityMultiplierCalculationJob.perform_later"
end

# Weekly budget distribution
every :sunday, at: '12:00 am' do
  runner "Decidim::VolunteerScheduler::BudgetDistributionJob.perform_later('weekly', nil, 1000.0)"
end

# Monthly budget distribution  
every '0 0 1 * *' do
  runner "Decidim::VolunteerScheduler::BudgetDistributionJob.perform_later('monthly', nil, 5000.0)"
end
```

Deploy cron jobs: `whenever --update-crontab`

### 3. Environment Variables

Add to your `.env` or environment configuration:

```bash
# Scicent Token API Integration
SCICENT_API_KEY=your_api_key_here
SCICENT_WEBHOOK_SECRET=your_webhook_secret_here

# Budget Pool Configuration  
VOLUNTEER_SCHEDULER_DAILY_BUDGET=100
VOLUNTEER_SCHEDULER_WEEKLY_BUDGET=1000
VOLUNTEER_SCHEDULER_MONTHLY_BUDGET=5000

# Redis Configuration (for Sidekiq)
REDIS_URL=redis://localhost:6379/0

# Commission Configuration
VOLUNTEER_SCHEDULER_MIN_COMMISSION=0.01
VOLUNTEER_SCHEDULER_MAX_MULTIPLIER=3.0
```

### 4. Webhook Configuration

#### Scicent Token Sales Webhook

Configure your Scicent token sales system to send webhooks to:
```
POST /volunteer_scheduler/webhooks/scicent_sale
```

**Required Headers:**
- `Content-Type: application/json`
- `X-Scicent-Signature: sha256=<signature>` (HMAC-SHA256 of payload)

**Payload Example:**
```json
{
  "user_id": 123,
  "amount": 100.50,
  "transaction_id": "scicent_tx_abc123",
  "currency": "SCICENT",
  "timestamp": "2024-12-15T10:30:00Z"
}
```

**Health Check:**
```
GET /volunteer_scheduler/webhooks/health
```

## Production Deployment

### 1. Process Management

#### With Systemd (Sidekiq)

Create `/etc/systemd/system/sidekiq.service`:
```ini
[Unit]
Description=Sidekiq Background Jobs
After=network.target

[Service]
Type=simple
User=your_app_user
WorkingDirectory=/path/to/your/app
Environment=RAILS_ENV=production
ExecStart=/usr/local/bin/bundle exec sidekiq -C config/sidekiq.yml
Restart=always

[Install]
WantedBy=multi-user.target
```

Enable and start:
```bash
sudo systemctl enable sidekiq
sudo systemctl start sidekiq
```

### 2. Monitoring

#### Queue Monitoring
Access Sidekiq web UI at: `/sidekiq` (if mounted)

#### Logs
Monitor job processing: `tail -f log/sidekiq.log`

#### Health Checks
```bash
# Check webhook health
curl http://your-app.com/volunteer_scheduler/webhooks/health

# Check queue sizes
bundle exec rails runner "puts Sidekiq::Queue.new.size"
```

## Testing

### Manual Commission Distribution Test

```ruby
# In Rails console
sale_data = {
  user_id: 1, # Existing user ID
  amount: 100.0,
  transaction_id: "test_#{Time.current.to_i}"
}

Decidim::VolunteerScheduler::CommissionDistributionJob.perform_now(sale_data)
```

### Activity Multiplier Test

```ruby  
# Test for specific organization
Decidim::VolunteerScheduler::ActivityMultiplierCalculationJob.perform_now(organization_id: 1)
```

### Budget Distribution Test

```ruby
# Test weekly distribution for organization with 500 token pool
Decidim::VolunteerScheduler::BudgetDistributionJob.perform_now('weekly', 1, 500.0)
```

## Troubleshooting

### Common Issues

**Jobs Not Processing:**
- Check background worker is running: `ps aux | grep sidekiq`
- Verify Redis connection: `redis-cli ping`
- Check queue status: `Sidekiq::Queue.new.size`

**Commission Distribution Fails:**
- Verify user exists and has volunteer profile
- Check referral chain integrity  
- Validate webhook signature configuration

**Activity Multipliers Not Updating:**
- Check for database performance issues with large datasets
- Verify date calculations in rolling window logic
- Review logs for individual profile calculation errors

**Budget Distribution Issues:**
- Ensure volunteers have minimum required task completions
- Check performance score calculations for edge cases
- Verify budget pool amounts are positive

### Debug Commands

```ruby
# Check failed jobs
Sidekiq::RetrySet.new.each { |job| puts job.error_message }

# Retry failed jobs
Sidekiq::RetrySet.new.retry_all

# Clear all queues (development only)
Sidekiq::Queue.new.clear
```

## Security Considerations

1. **Webhook Authentication**: Always verify signatures in production
2. **Rate Limiting**: Consider rate limiting webhook endpoints  
3. **Queue Access**: Restrict access to Sidekiq web UI
4. **Environment Variables**: Secure storage of API keys and secrets
5. **Audit Logging**: Monitor commission distributions for fraud

## Performance Optimization

1. **Batch Processing**: Process multiple profiles in batches for multiplier calculations
2. **Database Indexes**: Ensure proper indexing on date and status fields
3. **Queue Priorities**: Higher priority for commission distribution
4. **Redis Configuration**: Optimize Redis for job queue performance
5. **Monitoring**: Track job processing times and queue depths