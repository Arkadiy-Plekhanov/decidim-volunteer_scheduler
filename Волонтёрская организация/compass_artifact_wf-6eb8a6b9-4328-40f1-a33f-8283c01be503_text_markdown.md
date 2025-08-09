# Decidim Volunteer Scheduler Module Implementation Guide

Based on comprehensive research into Decidim 0.30+ development practices, this guide provides current implementation guidance for creating a sophisticated volunteer scheduler module with advanced referral systems, XP/leveling mechanics, token rewards, and real-time features.

## Current Decidim 0.30+ Development Foundation

The Decidim ecosystem has undergone significant architectural changes in version 0.30+, fundamentally altering how modules should be built and integrated.

### Major 0.30+ Changes Affecting Module Development

**Taxonomy System Revolution**: Decidim 0.30+ replaces the entire categorization system (Categories, Scopes, Areas, Process Types, Assembly Types) with a unified **Taxonomy System**. This change requires careful planning as it affects how volunteer opportunities, skills, and scheduling categories are organized.

**Component Generation Pattern**:
```bash
# Generate external module (recommended for volunteer scheduler)
decidim --component volunteer_scheduler --external --destination_folder ../decidim-module-volunteer-scheduler
```

**New Directory Structure** incorporates Webpacker changes:
```
decidim-module-volunteer-scheduler/
├── app/packs/                    # New Webpacker structure
│   ├── entrypoints/
│   └── src/
├── config/assets.rb              # Required for asset compilation
├── lib/decidim/volunteer_scheduler/
│   ├── component.rb              # Enhanced manifest with taxonomy support
│   └── engine.rb                 # Updated with asset path registration
└── spec/                         # Comprehensive test suite
```

### Component Manifest with Advanced Features

```ruby
# lib/decidim/volunteer_scheduler/component.rb
Decidim.register_component(:volunteer_scheduler) do |component|
  component.engine = VolunteerScheduler::Engine
  component.admin_engine = VolunteerScheduler::AdminEngine
  component.permissions_class_name = "Decidim::VolunteerScheduler::Permissions"

  # Taxonomy integration for volunteer categories/skills
  component.settings(:global) do |settings|
    settings.attribute :taxonomy_filters, type: :taxonomy_filters
    settings.attribute :enable_referral_system, type: :boolean, default: true
    settings.attribute :enable_xp_system, type: :boolean, default: true
    settings.attribute :token_reward_enabled, type: :boolean, default: true
  end

  # Export/import capabilities for volunteer data
  component.exports :volunteers do |exports|
    exports.collection { |component| Decidim::VolunteerScheduler::Volunteer.where(component: component) }
    exports.serializer Decidim::VolunteerScheduler::VolunteerSerializer
  end
end
```

## Advanced Referral System Implementation

### Database Architecture for 5-Level Hierarchical Tracking

The referral system requires sophisticated database design to handle deep hierarchies efficiently while preventing common pitfalls like referral loops.

**Core Schema with Hierarchy Column Pattern**:
```ruby
class CreateReferrals < ActiveRecord::Migration[7.0]
  def change
    create_table :decidim_volunteer_scheduler_referrals do |t|
      t.references :user, null: false, foreign_key: { to_table: :decidim_users }
      t.references :referrer, null: true, foreign_key: { to_table: :decidim_users }
      t.string :hierarchy, limit: 2700, null: false, default: ''
      t.integer :level, null: false, default: 0
      t.integer :ancestry_depth, default: 0
      t.decimal :commission_rate, precision: 5, scale: 4
      t.integer :direct_referrals_count, default: 0
      t.integer :total_network_size, default: 0
      t.timestamps
    end

    # Performance-critical indexes
    add_index :decidim_volunteer_scheduler_referrals, :hierarchy
    add_index :decidim_volunteer_scheduler_referrals, [:user_id, :level]
    add_index :decidim_volunteer_scheduler_referrals, :ancestry_depth
  end
end
```

**Referral Model with Loop Prevention**:
```ruby
class Decidim::VolunteerScheduler::Referral < ApplicationRecord
  include Decidim::HasComponent
  has_ancestry cache_depth: true, counter_cache: true
  
  belongs_to :user, class_name: "Decidim::User"
  belongs_to :referrer, class_name: "Decidim::User", optional: true
  
  COMMISSION_RATES = {
    0 => 0.15, 1 => 0.08, 2 => 0.05, 3 => 0.02, 4 => 0.01, 5 => 0.00
  }.freeze
  
  validate :prevent_referral_loops
  validate :max_depth_validation
  
  def calculate_network_commission(activity_points)
    path.reverse.each_with_index do |referral_record, index|
      next if index >= 5 || COMMISSION_RATES[index].zero?
      
      commission_points = activity_points * COMMISSION_RATES[index]
      Decidim::VolunteerScheduler::TokenService.award_tokens(
        referral_record.user, commission_points, "referral_level_#{index}"
      )
    end
  end
  
  private
  
  def prevent_referral_loops
    return unless referrer
    
    if user.referral&.descendant_ids&.include?(referrer.referral&.id)
      errors.add(:referrer, "would create a referral loop")
    end
  end
end
```

## XP/Leveling System Integration with Decidim's Framework

Decidim already includes a mature badge-based gamification system that can be extended with XP mechanics while maintaining compatibility.

### XP Database Schema Extension

```ruby
class CreateXpSystem < ActiveRecord::Migration[7.0]
  def change
    # User XP tracking
    create_table :decidim_volunteer_scheduler_user_scores do |t|
      t.references :decidim_user, null: false, foreign_key: true
      t.references :decidim_organization, null: false, foreign_key: true
      t.integer :total_xp, default: 0
      t.integer :current_level, default: 1
      t.integer :xp_to_next_level
      t.timestamps
    end

    # XP transaction log
    create_table :decidim_volunteer_scheduler_xp_transactions do |t|
      t.references :decidim_user, null: false, foreign_key: true
      t.string :action_type # 'volunteer_signup', 'event_completion', etc.
      t.integer :xp_gained
      t.references :trackable, polymorphic: true
      t.timestamps
    end
  end
end
```

### Integration with Decidim's Permission System

```ruby
module Decidim::VolunteerScheduler
  class Permissions < Decidim::DefaultPermissions
    def permissions
      return permission_action unless user
      
      case permission_action.subject
      when :volunteer_opportunity
        volunteer_opportunity_permission_action
      when :advanced_scheduling
        # Require level 3+ for advanced scheduling features
        if user_xp_level >= 3
          permission_action.allow!
        else
          permission_action.disallow!
        end
      end
      
      permission_action
    end
    
    private
    
    def user_xp_level
      user.volunteer_scheduler_user_score&.current_level || 1
    end
  end
end
```

## Token-Based Reward System Architecture

### Wallet Management with Rails Best Practices

```ruby
module Decidim::VolunteerScheduler
  class Wallet < ApplicationRecord
    belongs_to :user, class_name: "Decidim::User"
    has_many :transactions, class_name: "TokenTransaction"
    
    validates :balance, presence: true, numericality: { greater_than_or_equal_to: 0 }
    
    def add_tokens(amount, description = nil, category = 'earned')
      transaction do
        self.balance += amount
        save!
        
        transactions.create!(
          amount: amount,
          transaction_type: 'credit',
          description: description,
          category: category,
          balance_after: balance
        )
        
        # Broadcast real-time update if ActionCable available
        broadcast_balance_update if defined?(ActionCable)
      end
    end
    
    private
    
    def broadcast_balance_update
      ActionCable.server.broadcast(
        "wallet_#{user_id}",
        { type: 'balance_update', new_balance: balance }
      )
    end
  end
end
```

### Activity Multiplier System

```ruby
class Decidim::VolunteerScheduler::ActivityMultiplierService
  def initialize(user, activity)
    @user = user
    @activity = activity
  end
  
  def calculate_multiplier
    base_multiplier = 1.0
    base_multiplier *= engagement_streak_multiplier
    base_multiplier *= level_based_multiplier
    base_multiplier *= special_event_multiplier
    
    [base_multiplier, 6.0].min # Cap at 6x like EVE Online
  end
  
  private
  
  def engagement_streak_multiplier
    streak_days = @user.volunteer_engagement_streak
    case streak_days
    when 0..6 then 1.0
    when 7..13 then 1.2
    when 14..29 then 1.5
    else 2.0
    end
  end
end
```

## Background Job Processing and Real-Time Features

### Sidekiq Integration with Decidim Patterns

Decidim supports multiple background job backends, but Sidekiq with Redis provides the most robust solution for complex modules.

```ruby
# app/jobs/decidim/volunteer_scheduler/process_referral_job.rb
module Decidim::VolunteerScheduler
  class ProcessReferralJob < ApplicationJob
    queue_as :volunteer_scheduler
    
    def perform(user_id, activity_type, points)
      user = Decidim::User.find(user_id)
      return unless user.volunteer_scheduler_referral
      
      # Calculate multiplier
      multiplier = ActivityMultiplierService.new(user, activity_type).calculate_multiplier
      final_points = (points * multiplier).round
      
      # Process referral chain
      user.volunteer_scheduler_referral.calculate_network_commission(final_points)
      
      # Award XP
      XpService.award_xp(user, final_points, activity_type)
      
      # Broadcast updates
      WalletBroadcastService.broadcast_balance_update(user) if defined?(ActionCable)
    end
  end
end
```

### ActionCable Implementation for Real-Time Updates

**Optional ActionCable Integration** (maintains compatibility):
```ruby
# app/channels/decidim/volunteer_scheduler/notifications_channel.rb
module Decidim::VolunteerScheduler
  class NotificationsChannel < ApplicationCable::Channel
    def subscribed
      stream_from "volunteer_notifications_#{current_user.id}"
    end
    
    def unsubscribed
      stop_all_streams
    end
  end
end
```

**Broadcasting Service**:
```ruby
module Decidim::VolunteerScheduler
  class BroadcastService
    def self.broadcast_xp_update(user, xp_gained, new_level = nil)
      return unless defined?(ActionCable)
      
      ActionCable.server.broadcast(
        "volunteer_notifications_#{user.id}",
        {
          type: 'xp_update',
          xp_gained: xp_gained,
          total_xp: user.volunteer_scheduler_user_score.total_xp,
          level_up: new_level.present?,
          new_level: new_level
        }
      )
    end
  end
end
```

## Database Optimization for Hierarchical Data at Scale

### PostgreSQL ltree Extension for Referral Chains

PostgreSQL's ltree extension provides specialized functionality for hierarchical data structures, perfect for referral systems.

```sql
-- Enable ltree extension
CREATE EXTENSION ltree;

-- Referral hierarchy optimization
CREATE TABLE decidim_volunteer_scheduler_referral_paths (
    id SERIAL PRIMARY KEY,
    user_id INTEGER,
    referral_path ltree,
    created_at TIMESTAMP DEFAULT NOW()
);

-- Specialized indexes
CREATE INDEX referral_path_gist_idx ON decidim_volunteer_scheduler_referral_paths 
USING GIST (referral_path);
```

### Database Partitioning for Activity Logs

**Time-Based Partitioning for High-Volume Activity Data**:
```ruby
class CreatePartitionedActivities < ActiveRecord::Migration[7.0]
  def up
    execute <<-SQL
      CREATE TABLE decidim_volunteer_scheduler_activities_partitioned (
        id BIGSERIAL PRIMARY KEY,
        user_id INTEGER NOT NULL,
        activity_type VARCHAR(50),
        volunteer_opportunity_id INTEGER,
        points_earned INTEGER,
        created_at TIMESTAMP DEFAULT NOW()
      ) PARTITION BY RANGE (created_at);
    SQL
    
    # Create monthly partitions
    (12.months.ago.to_date..Date.current).group_by(&:beginning_of_month).each do |month, _|
      partition_name = "activities_#{month.strftime('%Y_%m')}"
      start_date = month.beginning_of_month
      end_date = month.end_of_month + 1.day
      
      execute <<-SQL
        CREATE TABLE #{partition_name} PARTITION OF decidim_volunteer_scheduler_activities_partitioned
        FOR VALUES FROM ('#{start_date}') TO ('#{end_date}');
      SQL
    end
  end
end
```

## Comprehensive Testing Strategy

### Decidim-Specific Testing Patterns

```ruby
# spec/system/volunteer_scheduler_workflow_spec.rb
require 'rails_helper'

RSpec.describe "Complete volunteer scheduler workflow", type: :system do
  let!(:organization) { create(:organization) }
  let!(:user) { create(:user, :confirmed, organization: organization) }
  let!(:component) { create(:volunteer_scheduler_component, organization: organization) }
  
  scenario "User completes referral and XP workflow" do
    # Test referral creation
    visit decidim.root_path
    login_as user, scope: :user
    
    # Navigate to volunteer opportunities
    click_link "Get involved"
    
    # Test volunteer signup with referral code
    fill_in "Referral code", with: referrer.referral_code.code
    click_button "Sign up to volunteer"
    
    # Verify XP and token rewards
    expect(page).to have_content("You earned 50 XP!")
    expect(page).to have_content("You received 10 tokens!")
    
    # Test real-time updates if ActionCable enabled
    if defined?(ActionCable)
      expect(page).to have_css(".notification.success", text: "Level up!")
    end
  end
end
```

### Performance Testing for Complex Operations

```ruby
# spec/performance/referral_chain_performance_spec.rb
RSpec.describe "Referral chain performance", :performance do
  it "processes deep referral chains efficiently" do
    # Create 5-level referral chain with 1000 users
    create_deep_referral_chain(depth: 5, width: 200)
    
    expect {
      Decidim::VolunteerScheduler::ProcessReferralJob.perform_now(
        leaf_user.id, 'event_completion', 100
      )
    }.to perform_under(200).ms.warmup(2).times
  end
end
```

## Production Deployment Architecture

### Infrastructure Scaling Patterns

**Medium-Scale Deployment (1,000-10,000 users)**:
- PostgreSQL with read replicas for analytics queries  
- Redis cluster for background jobs and ActionCable
- Separate Sidekiq worker processes for volunteer scheduler jobs
- CDN integration for static assets and user-generated content

**Large-Scale Deployment (10,000+ users)**:
- Kubernetes deployment with horizontal pod autoscaling
- AnyCable for WebSocket scaling (3x less memory usage)
- Database partitioning for activity logs and referral data
- Multi-region deployment for global volunteer coordination

### Security Hardening for Token Systems

```ruby
# Anti-fraud detection service
class Decidim::VolunteerScheduler::FraudDetectionService
  def initialize(user, action, params = {})
    @user = user
    @action = action
    @params = params
  end
  
  def suspicious_activity?
    rapid_fire_actions? || 
    unusual_referral_pattern? || 
    token_farming_behavior?
  end
  
  private
  
  def rapid_fire_actions?
    recent_actions = @user.volunteer_activities.where(created_at: 1.hour.ago..Time.current)
    recent_actions.count > HOURLY_ACTIVITY_LIMIT
  end
end
```

### Monitoring and Performance Analytics

**Key Metrics to Track**:
- Referral chain depth distribution and conversion rates
- XP earning patterns and level progression timelines  
- Token transaction volume and redemption patterns
- Background job processing times and failure rates
- WebSocket connection stability and message latency

```ruby
# Custom metrics tracking
class Decidim::VolunteerScheduler::MetricsService
  def self.track_referral_conversion(referrer, referred_user)
    Rails.logger.info(
      event: 'referral_conversion',
      referrer_id: referrer.id,
      referred_user_id: referred_user.id,
      referrer_level: referrer.volunteer_scheduler_referral&.level,
      organization_id: referrer.organization.id
    )
  end
end
```

## Implementation Roadmap

### Phase 1: Core Module Foundation (2-3 weeks)
1. Generate Decidim 0.30+ component with taxonomy support
2. Implement basic volunteer opportunity management
3. Set up component permissions and admin interface
4. Create comprehensive test suite foundation

### Phase 2: Advanced Features (3-4 weeks)
1. Implement 5-level referral system with loop prevention
2. Integrate XP/leveling system with Decidim's gamification
3. Build token-based reward system with fraud prevention
4. Add background job processing for all systems

### Phase 3: Real-Time and Optimization (2-3 weeks)
1. Implement ActionCable integration for live updates
2. Add database optimization and caching layers
3. Create comprehensive monitoring and analytics
4. Performance testing and optimization

### Phase 4: Production Deployment (1-2 weeks)
1. Set up production infrastructure with proper scaling
2. Implement security hardening and monitoring
3. Configure backup and disaster recovery procedures
4. Deploy with comprehensive testing in staging environment

This implementation guide provides a solid foundation for building a sophisticated Decidim volunteer scheduler module that leverages the latest development patterns while maintaining compatibility and performance at scale. The modular approach allows for gradual implementation and testing of each component before full production deployment.