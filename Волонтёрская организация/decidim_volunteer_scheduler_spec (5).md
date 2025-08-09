## 11. Deployment and Production Considerations

### 11.1 Database Optimization and Indexing Strategy
```ruby
# db/migrate/010_add_performance_indexes.rb
class AddPerformanceIndexes < ActiveRecord::Migration[6.1]
  def change
    # Composite indexes for frequent queries
    add_index :decidim_volunteer_scheduler_task_assignments, 
              [:assignee_id, :status, :due_date], 
              name: 'idx_assignments_user_status_due'
    
    add_index :decidim_volunteer_scheduler_task_assignments,
              [:task_template_id, :status],
              name: 'idx_assignments_template_status'
    
    add_index :decidim_volunteer_scheduler_volunteer_profiles,
              [:user_id, :level, :total_xp],
              name: 'idx_profiles_user_level_xp'
    
    add_index :decidim_volunteer_scheduler_referrals,
              [:referred_id, :level, :active],
              name: 'idx_referrals_referred_level_active'
    
    add_index :decidim_volunteer_scheduler_referrals,
              [:referrer_id, :active, :total_commission],
              name: 'idx_referrals_referrer_active_commission'
    
    add_index :decidim_volunteer_scheduler_scicent_transactions,
              [:user_id, :transaction_type, :status, :created_at],
              name: 'idx_transactions_user_type_status_date'
    
    # Partial indexes for active records
    add_index :decidim_volunteer_scheduler_task_templates,
              [:decidim_component_id, :level],
              where: "active = true",
              name: 'idx_templates_component_level_active'
    
    add_index :decidim_volunteer_scheduler_volunteer_profiles,
              [:last_activity_at],
              where: "last_activity_at > NOW() - INTERVAL '30 days'",
              name: 'idx_profiles_recent_activity'
  end
end

# config/initializers/volunteer_scheduler_performance.rb
module Decidim::VolunteerScheduler
  class PerformanceOptimizer
    class << self
      def configure_caching
        # Cache volunteer level capabilities
        Rails.cache.write(
          "volunteer_capabilities_#{Date.current}",
          VolunteerProfile::LEVEL_CAPABILITIES,
          expires_in: 1.day
        )
        
        # Cache XP thresholds
        Rails.cache.write(
          "xp_thresholds_#{Date.current}",
          VolunteerProfile::LEVEL_THRESHOLDS,
          expires_in: 1.day
        )
      end
      
      def optimize_queries
        # Preload associations to avoid N+1 queries
        TaskAssignment.includes(:task_template, :assignee)
        VolunteerProfile.includes(:user, :referrer, :referrals_made)
        Referral.includes(:referrer, :referred)
      end
    end
  end
end
```

### 11.2 Background Job Configuration
```ruby
# config/initializers/volunteer_scheduler_jobs.rb
Rails.application.configure do
  # Configure job priorities
  config.active_job.queue_adapter = :sidekiq
  
  # Job routing
  config.active_job.queue_name_prefix = "volunteer_scheduler"
  config.active_job.queue_name_delimiter = "_"
  
  # Configure job queues by priority
  Decidim::VolunteerScheduler::ReferralCommissionJob.queue_as :high_priority
  Decidim::VolunteerScheduler::ActivityMultiplierJob.queue_as :medium_priority
  Decidim::VolunteerScheduler::LevelUpNotificationJob.queue_as :low_priority
  Decidim::VolunteerScheduler::DailyAssignmentReminderJob.queue_as :scheduled
end

# app/jobs/decidim/volunteer_scheduler/base_job.rb
module Decidim::VolunteerScheduler
  class BaseJob < ApplicationJob
    queue_as :default
    
    retry_on StandardError, wait: :exponentially_longer, attempts: 3
    discard_on ActiveJob::DeserializationError
    
    around_perform do |job, block|
      Rails.logger.info "Starting #{job.class.name} with arguments: #{job.arguments}"
      start_time = Time.current
      
      block.call
      
      duration = Time.current - start_time
      Rails.logger.info "Completed #{job.class.name} in #{duration.round(2)}s"
    end
    
    private
    
    def with_error_handling
      yield
    rescue => e
      Rails.logger.error "Error in #{self.class.name}: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      
      # Send error notification to monitoring system
      ErrorNotificationService.notify(e, job_name: self.class.name, arguments: arguments)
      
      raise e
    end
  end
end

# config/schedule.rb (for whenever gem)
every 1.hour do
  runner "Decidim::VolunteerScheduler::ActivityMultiplierRecalculationJob.perform_later"
end

every 1.day, at: '9:00 am' do
  runner "Decidim::VolunteerScheduler::DailyAssignmentReminderJob.perform_later"
end

every 1.week, at: 'sunday 2:00 am' do
  runner "Decidim::VolunteerScheduler::WeeklyReportsJob.perform_later"
end
```

### 11.3 Monitoring and Observability
```ruby
# app/services/decidim/volunteer_scheduler/metrics_service.rb
module Decidim::VolunteerScheduler
  class MetricsService
    include Singleton
    
    def track_task_assignment(task_assignment)
      StatsD.increment('volunteer_scheduler.task_assigned')
      StatsD.histogram('volunteer_scheduler.assignment_level', task_assignment.task_template.level)
      StatsD.histogram('volunteer_scheduler.assignment_xp_reward', task_assignment.task_template.xp_reward)
    end
    
    def track_task_completion(task_assignment)
      StatsD.increment('volunteer_scheduler.task_completed')
      StatsD.timing('volunteer_scheduler.completion_time', completion_time(task_assignment))
      StatsD.histogram('volunteer_scheduler.xp_earned', task_assignment.xp_earned)
    end
    
    def track_level_up(volunteer_profile, old_level, new_level)
      StatsD.increment('volunteer_scheduler.level_up')
      StatsD.histogram('volunteer_scheduler.level_progression', new_level - old_level)
      StatsD.histogram('volunteer_scheduler.xp_at_level_up', volunteer_profile.total_xp)
    end
    
    def track_referral_commission(referral, commission_amount)
      StatsD.increment('volunteer_scheduler.referral_commission')
      StatsD.histogram('volunteer_scheduler.commission_amount', commission_amount)
      StatsD.histogram('volunteer_scheduler.commission_level', referral.level)
    end
    
    def track_api_request(endpoint, response_time)
      StatsD.timing("volunteer_scheduler.api.#{endpoint}.response_time", response_time)
      StatsD.increment("volunteer_scheduler.api.#{endpoint}.requests")
    end
    
    private
    
    def completion_time(task_assignment)
      return 0 unless task_assignment.completed_at && task_assignment.assigned_at
      
      (task_assignment.completed_at - task_assignment.assigned_at).to_i
    end
  end
end

# config/initializers/volunteer_scheduler_monitoring.rb
Rails.application.configure do
  # Application monitoring
  config.middleware.use "Decidim::VolunteerScheduler::MonitoringMiddleware"
  
  # Error tracking
  if Rails.env.production?
    Raven.configure do |config|
      config.tags = { component: 'volunteer_scheduler' }
    end
  end
  
  # Performance monitoring
  if defined?(NewRelic)
    NewRelic::Agent.add_custom_attributes({
      volunteer_scheduler_version: Decidim::VolunteerScheduler::VERSION
    })
  end
end
```

### 11.4 Security Hardening
```ruby
# app/controllers/concerns/decidim/volunteer_scheduler/security_headers.rb
module Decidim::VolunteerScheduler::SecurityHeaders
  extend ActiveSupport::Concern
  
  included do
    before_action :set_security_headers
    before_action :verify_referral_authenticity, only: [:create_referral]
    protect_from_forgery with: :exception
  end
  
  private
  
  def set_security_headers
    response.headers['X-Content-Type-Options'] = 'nosniff'
    response.headers['X-Frame-Options'] = 'DENY'
    response.headers['X-XSS-Protection'] = '1; mode=block'
    response.headers['Referrer-Policy'] = 'strict-origin-when-cross-origin'
  end
  
  def verify_referral_authenticity
    return unless params[:referral_code].present?
    
    # Rate limiting for referral code validation
    key = "referral_validation_#{request.remote_ip}"
    count = Rails.cache.read(key) || 0
    
    if count > 10
      Rails.logger.warn "Excessive referral validation attempts from #{request.remote_ip}"
      head :too_many_requests
      return
    end
    
    Rails.cache.write(key, count + 1, expires_in: 1.hour)
  end
end

# app/services/decidim/volunteer_scheduler/audit_service.rb
module Decidim::VolunteerScheduler
  class AuditService
    def self.log_sensitive_action(user, action, resource, details = {})
      Rails.logger.info({
        event: 'volunteer_scheduler_audit',
        user_id: user.id,
        action: action,
        resource_type: resource.class.name,
        resource_id: resource.id,
        ip_address: details[:ip_address],
        user_agent: details[:user_agent],
        timestamp: Time.current.iso8601,
        details: details.except(:ip_address, :user_agent)
      }.to_json)
      
      # Store in audit log table if required
      create_audit_log(user, action, resource, details) if Rails.env.production?
    end
    
    private
    
    def self.create_audit_log(user, action, resource, details)
      AuditLog.create!(
        user: user,
        action: action,
        auditable: resource,
        ip_address: details[:ip_address],
        user_agent: details[:user_agent],
        additional_data: details.except(:ip_address, :user_agent)
      )
    end
  end
end
```

### 11.5 Data Migration and Version Management
```ruby
# lib/decidim/volunteer_scheduler/data_migrator.rb
module Decidim::VolunteerScheduler
  class DataMigrator
    def self.migrate_from_version(from_version, to_version)
      case [from_version, to_version]
      when ['0.1.0', '0.2.0']
        migrate_0_1_to_0_2
      when ['0.2.0', '0.3.0']
        migrate_0_2_to_0_3
      else
        Rails.logger.warn "No migration path from #{from_version} to #{to_version}"
      end
    end
    
    def self.migrate_0_1_to_0_2
      Rails.logger.info "Starting migration from 0.1.0 to 0.2.0"
      
      # Migrate existing volunteer profiles to include new fields
      VolunteerProfile.find_each do |profile|
        profile.update!(
          activity_multiplier: 1.0,
          capabilities: profile.level_capabilities_for_migration
        )
      end
      
      # Create missing referral chains for existing referrals
      VolunteerProfile.where.not(referrer_id: nil).find_each do |profile|
        Referral.create_referral_chain(profile.referrer, profile.user)
      end
      
      Rails.logger.info "Completed migration from 0.1.0 to 0.2.0"
    end
    
    def self.rollback_to_version(target_version)
      Rails.logger.warn "Rolling back to version #{target_version}"
      
      case target_version
      when '0.1.0'
        rollback_to_0_1_0
      else
        Rails.logger.error "Cannot rollback to unknown version #{target_version}"
      end
    end
    
    private
    
    def self.rollback_to_0_1_0
      # Remove features introduced after 0.1.0
      Referral.delete_all
      VolunteerProfile.update_all(
        activity_multiplier: 1.0,
        capabilities: {},
        achievements: []
      )
    end
  end
end

# lib/tasks/volunteer_scheduler.rake
namespace :volunteer_scheduler do
  namespace :data do
    desc "Migrate data between versions"
    task :migrate, [:from_version, :to_version] => :environment do |_, args|
      from_version = args[:from_version]
      to_version = args[:to_version]
      
      unless from_version && to_version
        puts "Usage: rake volunteer_scheduler:data:migrate[from_version,to_version]"
        exit 1
      end
      
      Decidim::VolunteerScheduler::DataMigrator.migrate_from_version(from_version, to_version)
    end
    
    desc "Cleanup orphaned data"
    task cleanup: :environment do
      puts "Cleaning up orphaned volunteer data..."
      
      # Remove task assignments for deleted templates
      orphaned_assignments = Decidim::VolunteerScheduler::TaskAssignment
                              .left_joins(:task_template)
                              .where(decidim_volunteer_scheduler_task_templates: { id: nil })
      
      puts "Removing #{orphaned_assignments.count} orphaned assignments"
      orphaned_assignments.delete_all
      
      # Remove volunteer profiles for deleted users
      orphaned_profiles = Decidim::VolunteerScheduler::VolunteerProfile
                           .left_joins(:user)
                           .where(decidim_users: { id: nil })
      
      puts "Removing #{orphaned_profiles.count} orphaned profiles"
      orphaned_profiles.delete_all
      
      puts "Cleanup completed"
    end
    
    desc "Recalculate all activity multipliers"
    task recalculate_multipliers: :environment do
      puts "Recalculating activity multipliers for all users..."
      
      Decidim::VolunteerScheduler::VolunteerProfile.find_each do |profile|
        calculator = Decidim::VolunteerScheduler::ActivityMultiplierCalculator.new(profile.user)
        new_multiplier = calculator.calculate_multiplier
        
        if profile.activity_multiplier != new_multiplier
          profile.update!(activity_multiplier: new_multiplier)
          puts "Updated multiplier for user #{profile.user_id}: #{new_multiplier}"
        end
      end
      
      puts "Multiplier recalculation completed"
    end
  end
  
  namespace :reports do
    desc "Generate volunteer engagement report"
    task engagement: :environment do
      report = Decidim::VolunteerScheduler::EngagementReportGenerator.new
      puts report.generate_monthly_report(Date.current.beginning_of_month)
    end
    
    desc "Generate referral performance report"
    task referral_performance: :environment do
      report = Decidim::VolunteerScheduler::ReferralReportGenerator.new
      puts report.generate_commission_report(1.month.ago..Time.current)
    end
  end
end
```

### 11.6 Backup and Disaster Recovery
```ruby
# lib/decidim/volunteer_scheduler/backup_service.rb
module Decidim::VolunteerScheduler
  class BackupService
    def self.create_backup(backup_type = :full)
      timestamp = Time.current.strftime('%Y%m%d_%H%M%S')
      backup_path = Rails.root.join('tmp', 'volunteer_scheduler_backups')
      FileUtils.mkdir_p(backup_path)
      
      case backup_type
      when :full
        create_full_backup(backup_path, timestamp)
      when :profiles_only
        create_profiles_backup(backup_path, timestamp)
      when :transactions_only
        create_transactions_backup(backup_path, timestamp)
      end
    end
    
    def self.restore_backup(backup_file)
      backup_data = JSON.parse(File.read(backup_file))
      
      Rails.logger.info "Starting restore from #{backup_file}"
      
      ActiveRecord::Base.transaction do
        restore_volunteer_profiles(backup_data['volunteer_profiles'])
        restore_task_assignments(backup_data['task_assignments'])
        restore_referrals(backup_data['referrals'])
        restore_scicent_transactions(backup_data['scicent_transactions'])
      end
      
      Rails.logger.info "Backup restore completed successfully"
    end
    
    private
    
    def self.create_full_backup(backup_path, timestamp)
      backup_data = {
        timestamp: timestamp,
        version: Decidim::VolunteerScheduler::VERSION,
        volunteer_profiles: export_volunteer_profiles,
        task_assignments: export_task_assignments,
        referrals: export_referrals,
        scicent_transactions: export_scicent_transactions
      }
      
      backup_file = backup_path.join("full_backup_#{timestamp}.json")
      File.write(backup_file, JSON.pretty_generate(backup_data))
      
      Rails.logger.info "Full backup created: #{backup_file}"
      backup_file
    end
    
    def self.export_volunteer_profiles
      VolunteerProfile.includes(:user).map do |profile|
        {
          user_email: profile.user.email,
          level: profile.level,
          total_xp: profile.total_xp,
          total_scicent_earned: profile.total_scicent_earned,
          tasks_completed: profile.tasks_completed,
          activity_multiplier: profile.activity_multiplier,
          referral_code: profile.referral_code,
          capabilities: profile.capabilities,
          achievements: profile.achievements,
          created_at: profile.created_at,
          updated_at: profile.updated_at
        }
      end
    end
  end
end
```

This completes the comprehensive technical specification with detailed deployment and production considerations. The specification now includes:

## ✅ **Complete Coverage Areas:**

1. **Proper Decidim Architecture** - Following official patterns and generator usage
2. **Comprehensive Module Structure** - All necessary files and components
3. **Enhanced Component Registration** - With settings, exports, imports, and seeds
4. **Complete Database Schema** - Optimized with proper indexing
5. **Full Integration Points** - Events, content blocks, verification handlers, cells
6. **Asset Management** - Webpacker configuration and JavaScript components
7. **Real-time Features** - ActionCable integration for live updates
8. **Security Implementation** - Headers, audit logging, rate limiting
9. **Performance Optimization** - Database indexes, caching, monitoring
10. **Comprehensive Testing** - Factories, unit tests, integration tests, performance tests
11. **Production Deployment** - Monitoring, backup, migration strategies

The specification provides a complete blueprint for implementing a production-ready Decidim module that leverages all of Decidim's capabilities while adding sophisticated volunteer management and referral system features.## 11. Deployment and Production Considerations

### 11.1 Database Optimization and Indexing Strategy
```ruby
# db/migrate/010_add_performance_indexes.rb
class AddPerformanceIndexes < ActiveRecord::Migration[6.1]
  def change
    # Composite indexes for frequent queries
    add_index :decidim_volunteer_scheduler_task_assignments, 
              [:assignee_id, :status, :due_date], 
              name: 'idx_assignments_user_status_due'
    
    add_index :decidim_volunteer_scheduler_task_assignments,
              [:task_template_id, :status],
              name: 'idx_assignments_template_status'
    
    add_index :decidim_volunteer_scheduler_volunteer_profiles,
              [:user_id, :level, :total_xp],
              name: 'idx_profiles_user_level_xp'
    
    add_index :decidim_volunteer_scheduler_referrals,
              [:referred_id, :level, :active],
              name: 'idx_referrals_referred_level_active'
    
    add_index :decidim_volunteer_scheduler_referrals,
              [:referrer_id, :active, :total_commission],
              name: 'idx_referrals_referrer_active_commission'
    
    add_index :decidim_volunteer_scheduler_scicent_transactions,
              [:user_id, :transaction_type, :status, :created_at],
              name: 'idx_transactions_user_type_status_date'
    
    # Partial indexes for active records
    add_index :decidim_volunteer_scheduler_task_templates,
              [:decidim_component_id, :level],
              where: "active = true",
              name: 'idx_templates_component_level_active'
    
    add_index :decidim_volunteer_scheduler_volunteer_profiles,
              [:last_activity_at],
              where: "last_activity_at > NOW() - INTERVAL '30 days'",
              name: 'idx_profiles_recent_activity'
  end
end

# config/initializers/volunteer_scheduler_performance.rb
module Decidim::VolunteerScheduler
  # Enable query caching for frequent lookups
  class PerformanceOptimizer
    class << self
      def configure_caching
        # Cache volunteer level capabilities
        Rails.cache.write(
          "volunteer_capabilities_#{Date.current}",
          VolunteerProfile::LEVEL_CAPABILITIES,
          expires_in: 1.day
        )
        
        # Cache XP thresholds
        Rails.cache.write(
          "xp_thresholds_#{Date.current}",
          VolunteerProfile::LEVEL_THRESHOLDS,
          expires_in: 1.day
        )
      end### 7.4 Webpacker Asset Integration
```ruby
# lib/decidim/volunteer_scheduler/engine.rb
initializer "decidim.volunteer_scheduler.webpacker.assets_path" do
  Decidim.register_assets_path File.expand_path("app/packs", root)
end

# config/webpack/custom.js (to be added to main app)
const path = require('path')

module.exports = {
  resolve: {
    alias: {
      '@volunteer-scheduler': path.resolve(__dirname, '../../app/packs/src/decidim/volunteer_scheduler')
    }
  }
}

# app/packs/entrypoints/decidim_volunteer_scheduler.js
import "src/decidim/volunteer_scheduler/volunteer_dashboard"
import "src/decidim/volunteer_scheduler/task_management"
import "src/decidim/volunteer_scheduler/referral_system"
import "src/decidim/volunteer_scheduler/team_management"

# app/packs/entrypoints/decidim_volunteer_scheduler.scss
@import "~decidim-core/app/packs/stylesheets/decidim/utils/imports";
@import "src/decidim/volunteer_scheduler/volunteer_dashboard";
@import "src/decidim/volunteer_scheduler/task_cards";
@import "src/decidim/volunteer_scheduler/progress_tracker";
@import "src/decidim/volunteer_scheduler/referral_widget";
@import "src/decidim/volunteer_scheduler/team_components";

# app/packs/src/decidim/volunteer_scheduler/volunteer_dashboard.js
export default function() {
  const dashboardElement = document.querySelector('.volunteer-dashboard');
  if (!dashboardElement) return;
  
  // Activity multiplier updates
  const updateMultiplier = () => {
    fetch('/volunteer_scheduler/api/activity_multiplier', {
      headers: {
        'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content
      }
    })
    .then(response => response.json())
    .then(data => {
      const multiplierElement = document.querySelector('.activity-multiplier');
      if (multiplierElement) {
        multiplierElement.textContent = `${data.multiplier}x`;
      }
    });
  };
  
  // Auto-update every 30 seconds
  setInterval(updateMultiplier, 30000);
  
  // Real-time notifications for task updates
  if (window.DecidimCable) {
    window.DecidimCable.subscriptions.create({
      channel: "Decidim::VolunteerScheduler::TaskNotificationsChannel",
      user_id: dashboardElement.dataset.userId
    }, {
      received: function(data) {
        this.handleTaskNotification(data);
      },
      
      handleTaskNotification: function(data) {
        const notification = document.createElement('div');
        notification.className = 'alert alert-info task-notification';
        notification.innerHTML = data.message;
        
        const container = document.querySelector('.notifications-container');
        if (container) {
          container.appendChild(notification);
          setTimeout(() => notification.remove(), 5000);
        }
      }
    });
  }
  
  // Progress bar animations
  const progressBars = document.querySelectorAll('.xp-progress-bar');
  progressBars.forEach(bar => {
    const progress = bar.dataset.progress;
    setTimeout(() => {
      bar.style.width = `${progress}%`;
    }, 500);
  });
}

# app/packs/src/decidim/volunteer_scheduler/referral_system.js
export default function() {
  const referralElements = document.querySelectorAll('.referral-link-container');
  
  referralElements.forEach(container => {
    const copyButton = container.querySelector('.copy-referral-link');
    const linkInput = container.querySelector('.referral-link-input');
    
    if (copyButton && linkInput) {
      copyButton.addEventListener('click', () => {
        linkInput.select();
        document.execCommand('copy');
        
        const originalText = copyButton.textContent;
        copyButton.textContent = 'Copied!';
        copyButton.classList.add('success');
        
        setTimeout(() => {
          copyButton.textContent = originalText;
          copyButton.classList.remove('success');
        }, 2000);
      });
    }
  });
  
  // Referral tree visualization
  const referralTree = document.querySelector('.referral-tree');
  if (referralTree) {
    initializeReferralTreeVisualization(referralTree);
  }
}

function initializeReferralTreeVisualization(container) {
  // D3.js-based referral tree visualization
  const data = JSON.parse(container.dataset.referralData);
  
  // Implementation would use D3.js to create interactive referral tree
  console.log('Referral tree data:', data);
}
```

### 7.5 ActionCable Integration for Real-time Updates
```ruby
# app/channels/decidim/volunteer_scheduler/task_notifications_channel.rb
module Decidim::VolunteerScheduler
  class TaskNotificationsChannel < ApplicationCable::Channel
    def subscribed
      stream_from "volunteer_tasks_#{params[:user_id]}" if current_user
    end
    
    def unsubscribed
      stop_all_streams
    end
    
    private
    
    def current_user
      @current_user ||= env['warden'].user
    end
  end
end

# app/jobs/decidim/volunteer_scheduler/broadcast_task_update_job.rb
module Decidim::VolunteerScheduler
  class BroadcastTaskUpdateJob < ApplicationJob
    def perform(task_assignment, event_type)
      ActionCable.server.broadcast(
        "volunteer_tasks_#{task_assignment.assignee_id}",
        {
          type: event_type,
          message: generate_message(task_assignment, event_type),
          assignment_id: task_assignment.id
        }
      )
    end
    
    private
    
    def generate_message(assignment, event_type)
      case event_type
      when 'assigned'
        "New task assigned: #{assignment.task_template.title}"
      when 'completed'
        "Task completed! You earned #{assignment.xp_earned} XP"
      when 'reminder'
        "Reminder: Task '#{assignment.task_template.title}' is due soon"
      end
    end
  end
end
```# Decidim Volunteer Scheduler Module - Technical Specification

## 1. Overview

The **decidim-volunteer_scheduler** module is a comprehensive volunteer management system for Decidim that implements:
- Task assignment and tracking system
- XP-based leveling with capability unlocks
- 5-level referral system with commission distribution
- Scicent token rewards and sales tracking
- Activity multiplier system
- Team creation and mentoring capabilities

## 2. Module Architecture

### 2.1 Generator-Based Scaffolding
**Initial Setup**: Use Decidim's official generator to create the base structure:
```bash
decidim --component volunteer_scheduler
```

This generates the proper Decidim component scaffolding following official patterns.

### 2.2 Complete Module Structure
```
decidim-volunteer_scheduler/
├── app/
│   ├── cells/                           # Cell-based view components
│   │   └── decidim/volunteer_scheduler/
│   │       ├── volunteer_dashboard/
│   │       ├── task_card/
│   │       ├── progress_tracker/
│   │       └── referral_widget/
│   ├── commands/                        # Business logic commands
│   │   └── decidim/volunteer_scheduler/
│   │       ├── accept_task.rb
│   │       ├── complete_task.rb
│   │       ├── create_referral_chain.rb
│   │       └── calculate_commissions.rb
│   ├── controllers/
│   │   ├── decidim/volunteer_scheduler/
│   │   │   ├── application_controller.rb
│   │   │   ├── templates_controller.rb
│   │   │   ├── assignments_controller.rb
│   │   │   ├── teams_controller.rb
│   │   │   ├── referrals_controller.rb
│   │   │   └── dashboard_controller.rb
│   │   └── decidim/volunteer_scheduler/admin/
│   │       ├── application_controller.rb
│   │       ├── templates_controller.rb
│   │       ├── assignments_controller.rb
│   │       ├── volunteer_profiles_controller.rb
│   │       ├── xp_settings_controller.rb
│   │       └── reports_controller.rb
│   ├── events/                          # Event system integration
│   │   └── decidim/volunteer_scheduler/
│   │       ├── task_assigned_event.rb
│   │       ├── task_completed_event.rb
│   │       ├── level_up_event.rb
│   │       └── referral_reward_event.rb
│   ├── forms/                           # Form objects
│   │   └── decidim/volunteer_scheduler/
│   │       ├── task_template_form.rb
│   │       ├── task_submission_form.rb
│   │       └── team_creation_form.rb
│   ├── helpers/
│   │   └── decidim/volunteer_scheduler/
│   │       └── application_helper.rb
│   ├── jobs/
│   │   └── decidim/volunteer_scheduler/
│   │       ├── referral_commission_job.rb
│   │       ├── activity_multiplier_job.rb
│   │       ├── level_up_notification_job.rb
│   │       └── daily_assignment_reminder_job.rb
│   ├── models/
│   │   └── decidim/volunteer_scheduler/
│   │       ├── task_template.rb
│   │       ├── task_assignment.rb
│   │       ├── volunteer_profile.rb
│   │       ├── referral.rb
│   │       ├── scicent_transaction.rb
│   │       └── team.rb
│   ├── permissions/                     # Authorization logic
│   │   └── decidim/volunteer_scheduler/
│   │       └── permissions.rb
│   ├── queries/                         # Query objects
│   │   └── decidim/volunteer_scheduler/
│   │       ├── filtered_tasks.rb
│   │       └── volunteer_statistics.rb
│   ├── serializers/                     # API serializers
│   │   └── decidim/volunteer_scheduler/
│   │       ├── task_assignment_serializer.rb
│   │       └── volunteer_profile_serializer.rb
│   ├── types/                           # GraphQL types
│   │   └── decidim/volunteer_scheduler/
│   │       ├── volunteer_profile_type.rb
│   │       ├── task_template_type.rb
│   │       └── task_assignment_type.rb
│   └── views/
│       └── decidim/volunteer_scheduler/
├── config/
│   ├── routes.rb
│   └── locales/
│       ├── en.yml
│       ├── es.yml
│       ├── ca.yml
│       └── fr.yml
├── db/
│   └── migrate/
├── lib/
│   ├── decidim/
│   │   └── volunteer_scheduler/
│   │       ├── engine.rb
│   │       ├── admin_engine.rb
│   │       ├── component.rb
│   │       ├── test_utils.rb
│   │       └── version.rb
│   └── decidim-volunteer_scheduler.rb
├── app/packs/                           # Webpacker assets
│   ├── entrypoints/
│   │   ├── decidim_volunteer_scheduler.js
│   │   └── decidim_volunteer_scheduler.scss
│   ├── images/
│   └── stylesheets/
├── spec/                                # RSpec tests
│   ├── cells/
│   ├── commands/
│   ├── controllers/
│   ├── events/
│   ├── factories/
│   ├── forms/
│   ├── jobs/
│   ├── models/
│   ├── queries/
│   ├── serializers/
│   ├── system/                          # Integration tests
│   └── types/
├── decidim-volunteer_scheduler.gemspec
├── Gemfile
├── LICENSE-AGPLv3.txt
├── Rakefile
└── README.md
```

### 2.3 Component Registration

The module registers as a Decidim component following the standard pattern:

```ruby
# lib/decidim/volunteer_scheduler/component.rb
Decidim.register_component(:volunteer_scheduler) do |component|
  component.engine = Decidim::VolunteerScheduler::Engine
  component.admin_engine = Decidim::VolunteerScheduler::AdminEngine
  component.icon = "decidim/volunteer_scheduler/icon.svg"
  component.name = "volunteer_scheduler"
  
  # Lifecycle hooks
  component.on(:create) do |component_instance|
    Decidim::VolunteerScheduler::CreateDefaultTemplates.call(component_instance)
  end
  
  component.on(:destroy) do |component_instance|
    Decidim::VolunteerScheduler::CleanupComponentData.call(component_instance)
  end
  
  # Global settings (for the entire component lifecycle)
  component.settings(:global) do |settings|
    settings.attribute :enable_referral_system, type: :boolean, default: true
    settings.attribute :max_referral_levels, type: :integer, default: 5
    settings.attribute :enable_teams, type: :boolean, default: true
    settings.attribute :scicent_token_enabled, type: :boolean, default: true
    settings.attribute :default_xp_reward, type: :integer, default: 10
    settings.attribute :enable_activity_multiplier, type: :boolean, default: true
    settings.attribute :max_activity_multiplier, type: :text, default: "3.0"
    settings.attribute :enable_mentoring, type: :boolean, default: true
  end
  
  # Step settings (can change during different participatory process steps)
  component.settings(:step) do |settings|
    settings.attribute :task_creation_enabled, type: :boolean, default: true
    settings.attribute :assignment_deadline_days, type: :integer, default: 7
    settings.attribute :max_concurrent_assignments, type: :integer, default: 3
    settings.attribute :enable_public_leaderboard, type: :boolean, default: false
    settings.attribute :commission_rate_modifier, type: :text, default: "1.0"
  end
  
  # Export definitions for data portability
  component.exports :task_assignments do |exports|
    exports.collection do |component_instance|
      Decidim::VolunteerScheduler::TaskAssignment
        .joins(:task_template)
        .where(decidim_volunteer_scheduler_task_templates: { 
          decidim_component_id: component_instance.id 
        })
    end
    exports.serializer Decidim::VolunteerScheduler::TaskAssignmentSerializer
  end
  
  component.exports :volunteer_profiles do |exports|
    exports.collection do |component_instance|
      Decidim::VolunteerScheduler::VolunteerProfile
        .joins(user: :organization)
        .where(decidim_users: { decidim_organization_id: component_instance.organization.id })
    end
    exports.serializer Decidim::VolunteerScheduler::VolunteerProfileSerializer
  end
  
  component.exports :referral_data do |exports|
    exports.collection do |component_instance|
      Decidim::VolunteerScheduler::Referral
        .joins(referrer: :organization)
        .where(decidim_users: { decidim_organization_id: component_instance.organization.id })
    end
    exports.serializer Decidim::VolunteerScheduler::ReferralSerializer
  end
  
  # Import definitions for data loading
  component.imports :task_templates do |imports|
    imports.form_view = "decidim/volunteer_scheduler/admin/imports/task_templates_fields"
    imports.form_class_name = "Decidim::VolunteerScheduler::Admin::TaskTemplateImportForm"
    
    imports.messages do |msg|
      msg.set(:resource_name) { |count: 1| 
        I18n.t("decidim.volunteer_scheduler.admin.imports.resources.task_templates", count: count) 
      }
      msg.set(:title) { 
        I18n.t("decidim.volunteer_scheduler.admin.imports.title.task_templates") 
      }
      msg.set(:label) { 
        I18n.t("decidim.volunteer_scheduler.admin.imports.label.task_templates") 
      }
      msg.set(:help) { 
        I18n.t("decidim.volunteer_scheduler.admin.imports.help.task_templates") 
      }
    end
    
    imports.creator Decidim::VolunteerScheduler::TaskTemplateCreator
    
    imports.example do |import_component|
      organization = import_component.organization
      [
        organization.available_locales.map { |l| "title/#{l}" } + 
        organization.available_locales.map { |l| "description/#{l}" } +
        %w[level frequency xp_reward scicent_reward active],
        organization.available_locales.map { "Sample Task" } + 
        organization.available_locales.map { "Sample task description" } +
        ["1", "weekly", "50", "10.0", "true"]
      ]
    end
  end
  
  # Seeds for development/demo data
  component.seeds do |participatory_space|
    organization = participatory_space.organization
    
    component = Decidim::Component.create!(
      name: Decidim::Components::Namer.new(
        organization.available_locales,
        :volunteer_scheduler
      ).i18n_name,
      manifest_name: :volunteer_scheduler,
      published_at: Time.current,
      participatory_space: participatory_space
    )
    
    # Create sample task templates
    3.times do |i|
      Decidim::VolunteerScheduler::TaskTemplate.create!(
        component: component,
        title: Decidim::Faker::Localized.sentence(word_count: 3),
        description: Decidim::Faker::Localized.wrapped("<p>", "</p>") do
          Decidim::Faker::Localized.paragraph(sentence_count: 3)
        end,
        level: [1, 2, 3].sample,
        frequency: [:daily, :weekly, :monthly, :one_time].sample,
        category: [:outreach, :technical, :administrative, :creative, :research].sample,
        xp_reward: [10, 25, 50, 100].sample,
        scicent_reward: [5.0, 10.0, 25.0, 50.0].sample,
        active: true,
        max_assignments: [nil, 10, 50, 100].sample
      )
    end
  end
end
```

## 3. Core Models and Database Schema

### 3.1 Task Templates
**Purpose**: Define reusable task templates with XP rewards and requirements.

```ruby
# app/models/decidim/volunteer_scheduler/task_template.rb
class TaskTemplate < ApplicationRecord
  belongs_to :component, class_name: "Decidim::Component"
  has_many :task_assignments, dependent: :destroy
  
  enum level: { level1: 1, level2: 2, level3: 3 }
  enum frequency: { daily: 0, weekly: 1, monthly: 2, one_time: 3 }
  enum category: { 
    outreach: 0, technical: 1, administrative: 2, 
    creative: 3, research: 4, mentoring: 5 
  }
  
  validates :title, presence: true, length: { maximum: 150 }
  validates :description, presence: true
  validates :xp_reward, numericality: { greater_than: 0, less_than: 1000 }
  validates :scicent_reward, numericality: { greater_than_or_equal_to: 0 }
  
  scope :active, -> { where(active: true) }
  scope :available_for_level, ->(level) { where("level <= ?", level) }
  scope :by_category, ->(category) { where(category: category) }
end
```

**Database Schema**:
```sql
CREATE TABLE decidim_volunteer_scheduler_task_templates (
  id BIGINT PRIMARY KEY,
  decidim_component_id BIGINT NOT NULL,
  title VARCHAR(150) NOT NULL,
  description TEXT NOT NULL,
  level INTEGER NOT NULL DEFAULT 1,
  frequency INTEGER NOT NULL DEFAULT 0,
  category INTEGER NOT NULL DEFAULT 0,
  xp_reward INTEGER NOT NULL DEFAULT 10,
  scicent_reward DECIMAL(10,2) DEFAULT 0,
  active BOOLEAN NOT NULL DEFAULT TRUE,
  available_from TIMESTAMP,
  available_until TIMESTAMP,
  max_assignments INTEGER,
  requirements TEXT,
  instructions JSONB DEFAULT '{}',
  metadata JSONB DEFAULT '{}',
  created_at TIMESTAMP NOT NULL,
  updated_at TIMESTAMP NOT NULL
);
```

### 3.2 Task Assignments
**Purpose**: Track individual task assignments to volunteers.

```ruby
# app/models/decidim/volunteer_scheduler/task_assignment.rb
class TaskAssignment < ApplicationRecord
  belongs_to :task_template
  belongs_to :assignee, class_name: "Decidim::User"
  belongs_to :reviewer, class_name: "Decidim::User", optional: true
  
  enum status: { 
    pending: 0, in_progress: 1, submitted: 2, 
    completed: 3, rejected: 4, cancelled: 5 
  }
  
  validates :assignee, presence: true
  validates :assigned_at, presence: true
  validate :assignee_can_accept_task
  
  scope :overdue, -> { where("due_date < ? AND status IN (?)", 
                             Time.current, [statuses[:pending], statuses[:in_progress]]) }
  scope :due_soon, -> { where("due_date BETWEEN ? AND ?", 
                              Time.current, 1.day.from_now) }
end
```

### 3.3 Volunteer Profiles
**Purpose**: Extended user profiles with XP, levels, and referral tracking.

```ruby
# app/models/decidim/volunteer_scheduler/volunteer_profile.rb
class VolunteerProfile < ApplicationRecord
  belongs_to :user, class_name: "Decidim::User"
  belongs_to :referrer, class_name: "Decidim::User", optional: true
  
  has_many :task_assignments, foreign_key: :assignee_id, primary_key: :user_id
  has_many :team_memberships, dependent: :destroy
  has_many :teams, through: :team_memberships
  has_many :referrals_made, class_name: "Referral", 
           foreign_key: :referrer_id, primary_key: :user_id
  
  validates :referral_code, presence: true, uniqueness: true
  validates :level, inclusion: { in: 1..3 }
  
  # XP and Level Management
  LEVEL_THRESHOLDS = { 1 => 0, 2 => 100, 3 => 500 }.freeze
  LEVEL_CAPABILITIES = {
    1 => %w[basic_tasks],
    2 => %w[basic_tasks team_creation mentoring intermediate_tasks],
    3 => %w[basic_tasks team_creation mentoring intermediate_tasks 
            advanced_tasks team_leadership admin_tasks]
  }.freeze
  
  def level_up_if_needed!
    new_level = calculate_level_from_xp
    if new_level > level
      update!(level: new_level)
      LevelUpNotificationJob.perform_later(user_id)
      unlock_capabilities(new_level)
    end
  end
  
  def can_access_capability?(capability)
    current_capabilities.include?(capability.to_s)
  end
  
  private
  
  def current_capabilities
    LEVEL_CAPABILITIES[level] || []
  end
end
```

### 3.4 Referral System
**Purpose**: 5-level referral tracking with commission distribution.

```ruby
# app/models/decidim/volunteer_scheduler/referral.rb
class Referral < ApplicationRecord
  belongs_to :referrer, class_name: "Decidim::User"
  belongs_to :referred, class_name: "Decidim::User"
  
  validates :level, inclusion: { in: 1..5 }
  validates :commission_rate, numericality: { 
    greater_than: 0, less_than_or_equal_to: 1 
  }
  
  # Commission rates decrease by level
  COMMISSION_RATES = {
    1 => 0.10, # 10% direct referral
    2 => 0.08, # 8% second level
    3 => 0.06, # 6% third level
    4 => 0.04, # 4% fourth level
    5 => 0.02  # 2% fifth level
  }.freeze
  
  def self.create_referral_chain(referrer, referred)
    transaction do
      current_referrer = referrer
      level = 1
      
      while current_referrer && level <= 5
        create!(
          referrer: current_referrer,
          referred: referred,
          level: level,
          commission_rate: COMMISSION_RATES[level],
          active: true
        )
        
        current_referrer = current_referrer.volunteer_profile&.referrer
        level += 1
      end
    end
  end
end
```

### 3.5 Scicent Transactions
**Purpose**: Track Scicent token transactions and commissions.

```ruby
# app/models/decidim/volunteer_scheduler/scicent_transaction.rb
class ScicentTransaction < ApplicationRecord
  belongs_to :user, class_name: "Decidim::User"
  belongs_to :source, polymorphic: true # TaskAssignment, Referral, etc.
  
  enum transaction_type: {
    task_reward: 0,
    referral_commission: 1,
    sale_commission: 2,
    admin_bonus: 3,
    team_bonus: 4
  }
  
  enum status: { pending: 0, completed: 1, failed: 2 }
  
  validates :amount, numericality: { greater_than: 0 }
  validates :transaction_type, presence: true
  
  scope :by_user, ->(user) { where(user: user) }
  scope :successful, -> { where(status: :completed) }
end
```

## 4. Integration with Decidim Features

### 4.1 User Model Extension
```ruby
# app/models/concerns/decidim/volunteer_scheduler/user_extensions.rb
module Decidim::VolunteerScheduler::UserExtensions
  extend ActiveSupport::Concern
  
  included do
    has_one :volunteer_profile, 
            class_name: "Decidim::VolunteerScheduler::VolunteerProfile",
            dependent: :destroy
    
    has_many :task_assignments, 
             class_name: "Decidim::VolunteerScheduler::TaskAssignment",
             foreign_key: :assignee_id
    
    after_create :create_volunteer_profile_if_needed
  end
  
  def volunteer?
    volunteer_profile.present?
  end
  
  def volunteer_level
    volunteer_profile&.level || 1
  end
  
  def total_volunteer_xp
    volunteer_profile&.total_xp || 0
  end
  
  def referral_link
    return nil unless volunteer_profile
    
    Rails.application.routes.url_helpers.new_user_registration_url(
      ref: volunteer_profile.referral_code
    )
  end
end
```

### 4.2 Menu Integration
```ruby
# lib/decidim/volunteer_scheduler/engine.rb
initializer "decidim.volunteer_scheduler.menu" do
  Decidim.menu :user_menu do |menu|
    menu.item I18n.t("menu.volunteer_dashboard", scope: "decidim.volunteer_scheduler"),
              decidim_volunteer_scheduler.root_path,
              position: 2.5,
              if: proc { current_user&.volunteer? },
              active: :inclusive
  end
  
  Decidim.menu :admin_menu do |menu|
    menu.item I18n.t("menu.volunteer_management", scope: "decidim.volunteer_scheduler.admin"),
              decidim_volunteer_scheduler.admin_root_path,
              position: 7,
              active: :inclusive,
              if: allowed_to?(:enter, :space_area, space_name: :admin)
  end
end
```

### 4.4 Event System Integration
```ruby
# app/events/decidim/volunteer_scheduler/task_assigned_event.rb
module Decidim::VolunteerScheduler
  class TaskAssignedEvent < Decidim::Events::SimpleEvent
    include Decidim::Events::EmailEvent
    include Decidim::Events::NotificationEvent
    
    def resource_path
      Decidim::VolunteerScheduler::Engine.routes.url_helpers
        .assignment_path(resource)
    end
    
    def resource_title
      resource.task_template.title
    end
  end
end

# Event registration in engine.rb
initializer "decidim.volunteer_scheduler.events" do
  Decidim::EventsManager.subscribe("decidim.volunteer_scheduler.task_assigned") do |event_name, data|
    Decidim::VolunteerScheduler::TaskAssignedEvent.new(
      resource: data[:task_assignment],
      event_name: event_name,
      user: data[:user],
      extra: data[:extra] || {}
    ).perform_later
  end
  
  Decidim::EventsManager.subscribe("decidim.volunteer_scheduler.level_up") do |event_name, data|
    Decidim::VolunteerScheduler::LevelUpEvent.new(
      resource: data[:volunteer_profile],
      event_name: event_name,
      user: data[:user],
      extra: { new_level: data[:new_level] }
    ).perform_later
  end
end
```

### 4.5 Content Blocks for Homepage Integration
```ruby
# app/cells/decidim/volunteer_scheduler/content_blocks/volunteer_stats_cell.rb
module Decidim::VolunteerScheduler::ContentBlocks
  class VolunteerStatsCell < Decidim::ViewModel
    include Decidim::ApplicationHelper
    
    def show
      return unless current_user&.volunteer?
      render
    end
    
    private
    
    def volunteer_profile
      @volunteer_profile ||= current_user.volunteer_profile
    end
    
    def recent_assignments
      @recent_assignments ||= volunteer_profile.task_assignments
                                             .recent
                                             .limit(3)
                                             .includes(:task_template)
    end
    
    def next_level_progress
      volunteer_profile.progress_to_next_level
    end
  end
end

# Register content block in engine.rb
initializer "decidim.volunteer_scheduler.content_blocks" do
  Decidim.content_blocks.register(:homepage, :volunteer_stats) do |content_block|
    content_block.cell = "decidim/volunteer_scheduler/content_blocks/volunteer_stats"
    content_block.public_name_key = "decidim.volunteer_scheduler.content_blocks.volunteer_stats.name"
    content_block.settings_form_cell = "decidim/volunteer_scheduler/content_blocks/volunteer_stats_settings_form"
    
    content_block.settings do |settings|
      settings.attribute :show_leaderboard, type: :boolean, default: false
      settings.attribute :max_items, type: :integer, default: 5
    end
  end
  
  Decidim.content_blocks.register(:homepage, :volunteer_leaderboard) do |content_block|
    content_block.cell = "decidim/volunteer_scheduler/content_blocks/volunteer_leaderboard"
    content_block.public_name_key = "decidim.volunteer_scheduler.content_blocks.volunteer_leaderboard.name"
  end
end
```

### 4.6 Verification Handler Integration
```ruby
# lib/decidim/volunteer_scheduler/verification_handler.rb
module Decidim::VolunteerScheduler
  class VerificationHandler < Decidim::AuthorizationHandler
    attribute :volunteer_level, Integer
    attribute :completed_tasks, Integer
    
    validates :volunteer_level, inclusion: { in: [1, 2, 3] }
    validates :completed_tasks, numericality: { greater_than_or_equal_to: 0 }
    
    def authorization_attributes
      {
        "volunteer_level" => volunteer_level,
        "completed_tasks" => completed_tasks,
        "referral_count" => user.volunteer_profile&.referrals_made&.count || 0
      }
    end
    
    private
    
    def user_profile
      @user_profile ||= user.volunteer_profile
    end
    
    def volunteer_level
      user_profile&.level || 1
    end
    
    def completed_tasks
      user_profile&.tasks_completed || 0
    end
  end
end

# Register verification handler in engine.rb
initializer "decidim.volunteer_scheduler.verification_workflow" do |_app|
  Decidim::Verifications.register_workflow(:volunteer_verification) do |workflow|
    workflow.handler = Decidim::VolunteerScheduler::VerificationHandler
  end
end
```

### 4.7 Cell-Based View Components
```ruby
# app/cells/decidim/volunteer_scheduler/task_card_cell.rb
module Decidim::VolunteerScheduler
  class TaskCardCell < Decidim::ViewModel
    include Decidim::ApplicationHelper
    include Decidim::VolunteerScheduler::ApplicationHelper
    
    def show
      cell(
        "decidim/card", 
        model,
        full_badge: full_badge,
        statuses: statuses,
        context: { 
          extra_classes: ["task-card"],
          description: task_description 
        }
      )
    end
    
    private
    
    def task_description
      decidim_sanitize_editor(translated_attribute(model.description))
    end
    
    def full_badge
      {
        name: badge_name,
        color: badge_color
      }
    end
    
    def badge_name
      t("decidim.volunteer_scheduler.task_templates.level", level: model.level)
    end
    
    def badge_color
      case model.level
      when 1 then "success"
      when 2 then "warning" 
      when 3 then "alert"
      end
    end
    
    def statuses
      [
        {
          key: "xp_reward",
          value: "#{model.xp_reward} XP"
        },
        {
          key: "scicent_reward", 
          value: "#{model.scicent_reward} SCT"
        }
      ]
    end
  end
end

# app/cells/decidim/volunteer_scheduler/progress_tracker_cell.rb
module Decidim::VolunteerScheduler
  class ProgressTrackerCell < Decidim::ViewModel
    def show
      return unless current_user&.volunteer?
      render
    end
    
    private
    
    def volunteer_profile
      @volunteer_profile ||= current_user.volunteer_profile
    end
    
    def current_level
      volunteer_profile.level
    end
    
    def current_xp
      volunteer_profile.total_xp
    end
    
    def next_level_xp
      Decidim::VolunteerScheduler::VolunteerProfile::LEVEL_THRESHOLDS[current_level + 1]
    end
    
    def progress_percentage
      return 100 if next_level_xp.nil?
      
      current_level_xp = Decidim::VolunteerScheduler::VolunteerProfile::LEVEL_THRESHOLDS[current_level]
      progress = ((current_xp - current_level_xp).to_f / (next_level_xp - current_level_xp)) * 100
      [progress, 100].min.round(2)
    end
    
    def capabilities
      volunteer_profile.current_level_capabilities
    end
  end
end
```

## 5. Business Logic Components

### 5.1 Task Assignment Flow
```ruby
# app/commands/decidim/volunteer_scheduler/accept_task.rb
class AcceptTask < Rectify::Command
  def initialize(task_template, user)
    @task_template = task_template
    @user = user
  end
  
  def call
    return broadcast(:invalid) unless can_accept_task?
    
    transaction do
      assignment = create_assignment
      update_user_activity_multiplier
      notify_assignment_created(assignment)
      
      broadcast(:ok, assignment)
    end
  rescue StandardError => e
    broadcast(:invalid, e.message)
  end
  
  private
  
  def can_accept_task?
    @task_template.available_for_user?(@user) &&
      !has_pending_assignment? &&
      meets_level_requirement?
  end
  
  def create_assignment
    TaskAssignment.create!(
      task_template: @task_template,
      assignee: @user,
      status: :pending,
      assigned_at: Time.current,
      due_date: @task_template.due_date_for_assignment
    )
  end
end
```

### 5.2 Referral Commission Distribution
```ruby
# app/jobs/decidim/volunteer_scheduler/referral_commission_job.rb
class ReferralCommissionJob < ApplicationJob
  def perform(user_id, scicent_amount)
    user = Decidim::User.find(user_id)
    referrals = Referral.where(referred: user).includes(:referrer)
    
    referrals.each do |referral|
      commission_amount = scicent_amount * referral.commission_rate
      next if commission_amount <= 0
      
      create_commission_transaction(referral, commission_amount)
      update_referrer_multiplier(referral.referrer)
    end
  end
  
  private
  
  def create_commission_transaction(referral, amount)
    ScicentTransaction.create!(
      user: referral.referrer,
      source: referral,
      transaction_type: :referral_commission,
      amount: amount,
      status: :completed,
      description: "Referral commission from #{referral.referred.name}"
    )
  end
end
```

### 5.3 Activity Multiplier System
```ruby
# app/services/decidim/volunteer_scheduler/activity_multiplier_calculator.rb
class ActivityMultiplierCalculator
  def initialize(user)
    @user = user
    @profile = user.volunteer_profile
  end
  
  def calculate_multiplier
    base_multiplier = 1.0
    
    # Level bonus
    level_bonus = (@profile.level - 1) * 0.1
    
    # Activity bonus (based on recent task completion)
    activity_bonus = calculate_activity_bonus
    
    # Referral bonus (based on active referrals)
    referral_bonus = calculate_referral_bonus
    
    # Team leadership bonus
    leadership_bonus = calculate_leadership_bonus
    
    [base_multiplier + level_bonus + activity_bonus + referral_bonus + leadership_bonus, 3.0].min
  end
  
  private
  
  def calculate_activity_bonus
    recent_completions = @profile.task_assignments
                                .completed
                                .where("completed_at > ?", 1.month.ago)
                                .count
    
    (recent_completions / 10.0) * 0.05 # 5% bonus per 10 completed tasks
  end
  
  def calculate_referral_bonus
    active_referrals = @profile.referrals_made
                              .joins(:referred)
                              .merge(VolunteerProfile.where("last_activity_at > ?", 1.week.ago))
                              .count
    
    (active_referrals / 5.0) * 0.1 # 10% bonus per 5 active referrals
  end
end
```

## 6. User Interface Components

### 6.1 Volunteer Dashboard
- **Task Board**: Available tasks filtered by user level and capabilities
- **Progress Tracker**: XP progress, level status, next level requirements
- **Referral Center**: Referral link, commission tracking, referral tree view
- **Team Management**: Team creation, member management, performance metrics
- **Achievement Gallery**: Unlocked achievements and capabilities

### 6.2 Admin Interface
- **Template Management**: Create, edit, and manage task templates
- **Assignment Oversight**: Review submissions, approve/reject tasks
- **Volunteer Analytics**: Performance metrics, level distribution, activity trends
- **Commission Management**: Track and manage Scicent token distributions
- **System Settings**: Configure XP thresholds, commission rates, multipliers

## 7. Integration Points

### 7.1 Decidim Notifications
```ruby
# Integration with Decidim's notification system
Decidim::EventsManager.subscribe("decidim.volunteer_scheduler.task_assigned") do |event_name, data|
  TaskAssignmentNotification.deliver_later(
    data[:task_assignment],
    data[:user]
  )
end
```

### 7.2 Decidim Search Integration
```ruby
# app/models/decidim/volunteer_scheduler/task_template.rb
include Decidim::Searchable
include Decidim::Traceable

searchable_fields({
  scope_id: :decidim_scope_id,
  participatory_space: { component: :participatory_space },
  A: :title,
  D: :description
})
```

### 7.3 GraphQL API Extension
```ruby
# app/types/decidim/volunteer_scheduler/volunteer_profile_type.rb
module Decidim::VolunteerScheduler
  class VolunteerProfileType < Decidim::Api::Types::BaseObject
    field :level, GraphQL::Types::Int, null: false
    field :total_xp, GraphQL::Types::Int, null: false
    field :current_capabilities, [GraphQL::Types::String], null: false
    field :referral_code, GraphQL::Types::String, null: false
    field :activity_multiplier, GraphQL::Types::Float, null: false
  end
end
```

## 8. Security Considerations

### 8.1 Authorization Checks
- All task assignments validate user level and capabilities
- Referral code generation uses cryptographically secure random strings
- Commission calculations are validated against business rules
- Admin actions require proper authorization levels

### 8.2 Data Protection
- Personal referral information is protected
- Commission data is encrypted at rest
- Activity logs maintain audit trails
- GDPR compliance for user data export/deletion

## 9. Performance Considerations

### 9.1 Database Optimizations
- Proper indexing on frequently queried fields
- Efficient queries for referral chain calculations
- Background job processing for commission distributions
- Caching of frequently accessed volunteer statistics

### 9.2 Scalability Features
- Asynchronous processing of commission calculations
- Batch updates for activity multiplier recalculations
- Efficient pagination for large datasets
- Database connection pooling for high concurrency

## 10. Testing Strategy

### 10.1 Comprehensive Test Coverage
```ruby
# spec/factories/decidim/volunteer_scheduler/task_templates.rb
FactoryBot.define do
  factory :task_template, class: "Decidim::VolunteerScheduler::TaskTemplate" do
    component { create(:volunteer_scheduler_component) }
    title { generate_localized_title }
    description { Decidim::Faker::Localized.wrapped("<p>", "</p>") { generate(:content) } }
    level { [1, 2, 3].sample }
    frequency { [:daily, :weekly, :monthly, :one_time].sample }
    category { [:outreach, :technical, :administrative, :creative, :research].sample }
    xp_reward { Faker::Number.between(from: 10, to: 100) }
    scicent_reward { Faker::Number.decimal(l_digits: 2, r_digits: 2) }
    active { true }
    available_from { 1.week.ago }
    available_until { 1.month.from_now }
    max_assignments { [nil, 10, 50, 100].sample }
    
    trait :level_1 do
      level { 1 }
      xp_reward { 10 }
    end
    
    trait :level_2 do
      level { 2 }
      xp_reward { 25 }
    end
    
    trait :level_3 do
      level { 3 }
      xp_reward { 50 }
    end
    
    trait :inactive do
      active { false }
    end
    
    trait :expired do
      available_until { 1.week.ago }
    end
    
    trait :unlimited_assignments do
      max_assignments { nil }
    end
  end
  
  factory :volunteer_scheduler_component, parent: :component do
    name { Decidim::Components::Namer.new(participatory_space.organization.available_locales, :volunteer_scheduler).i18n_name }
    manifest_name { :volunteer_scheduler }
    participatory_space { create(:participatory_process, :with_steps) }
  end
end

# spec/factories/decidim/volunteer_scheduler/volunteer_profiles.rb
FactoryBot.define do
  factory :volunteer_profile, class: "Decidim::VolunteerScheduler::VolunteerProfile" do
    user { create(:user, :confirmed) }
    level { 1 }
    total_xp { 0 }
    total_scicent_earned { 0.0 }
    referral_scicent_earned { 0.0 }
    tasks_completed { 0 }
    activity_multiplier { 1.0 }
    referral_code { SecureRandom.alphanumeric(8).upcase }
    capabilities { { "basic_tasks" => true } }
    achievements { [] }
    last_activity_at { Time.current }
    
    trait :level_2 do
      level { 2 }
      total_xp { 150 }
      capabilities { { "basic_tasks" => true, "team_creation" => true, "mentoring" => true } }
    end
    
    trait :level_3 do
      level { 3 }
      total_xp { 600 }
      capabilities { { 
        "basic_tasks" => true, 
        "team_creation" => true, 
        "mentoring" => true,
        "advanced_tasks" => true,
        "team_leadership" => true 
      } }
    end
    
    trait :with_referrer do
      referrer { create(:user, :confirmed) }
    end
    
    trait :experienced do
      tasks_completed { 25 }
      total_xp { 300 }
      activity_multiplier { 1.5 }
    end
  end
end

# spec/factories/decidim/volunteer_scheduler/task_assignments.rb
FactoryBot.define do
  factory :task_assignment, class: "Decidim::VolunteerScheduler::TaskAssignment" do
    task_template { create(:task_template) }
    assignee { create(:user, :confirmed) }
    status { :pending }
    assigned_at { Time.current }
    due_date { 1.week.from_now }
    
    trait :in_progress do
      status { :in_progress }
      started_at { 1.day.ago }
    end
    
    trait :completed do
      status { :completed }
      started_at { 3.days.ago }
      completed_at { 1.day.ago }
      report { "Task completed successfully with all requirements met." }
      xp_earned { task_template.xp_reward }
      scicent_earned { task_template.scicent_reward }
    end
    
    trait :overdue do
      status { :pending }
      due_date { 2.days.ago }
    end
    
    trait :with_submission do
      status { :submitted }
      report { "Detailed report of task completion with evidence and outcomes." }
      submission_data { { 
        "files" => ["report.pdf", "screenshots.zip"],
        "notes" => "Additional implementation notes"
      } }
    end
  end
end

# spec/factories/decidim/volunteer_scheduler/referrals.rb
FactoryBot.define do
  factory :referral, class: "Decidim::VolunteerScheduler::Referral" do
    referrer { create(:user, :confirmed) }
    referred { create(:user, :confirmed) }
    level { 1 }
    commission_rate { Decidim::VolunteerScheduler::Referral::COMMISSION_RATES[level] }
    total_commission { 0.0 }
    active { true }
    
    trait :level_2 do
      level { 2 }
      commission_rate { 0.08 }
    end
    
    trait :level_3 do
      level { 3 }
      commission_rate { 0.06 }
    end
    
    trait :with_commissions do
      total_commission { 50.0 }
    end
    
    trait :inactive do
      active { false }
    end
  end
end
```

### 10.2 Model Specs
```ruby
# spec/models/decidim/volunteer_scheduler/volunteer_profile_spec.rb
require "rails_helper"

module Decidim::VolunteerScheduler
  RSpec.describe VolunteerProfile, type: :model do
    subject { build(:volunteer_profile) }
    
    it { is_expected.to be_valid }
    
    describe "associations" do
      it { is_expected.to belong_to(:user) }
      it { is_expected.to belong_to(:referrer).optional }
      it { is_expected.to have_many(:task_assignments) }
      it { is_expected.to have_many(:referrals_made) }
    end
    
    describe "validations" do
      it { is_expected.to validate_presence_of(:referral_code) }
      it { is_expected.to validate_uniqueness_of(:referral_code) }
      it { is_expected.to validate_inclusion_of(:level).in_array([1, 2, 3]) }
    end
    
    describe "#add_xp" do
      let(:profile) { create(:volunteer_profile, total_xp: 50) }
      
      context "when XP doesn't trigger level up" do
        it "adds XP without changing level" do
          expect { profile.add_xp(30) }
            .to change(profile, :total_xp).from(50).to(80)
            .and not_change(profile, :level)
        end
      end
      
      context "when XP triggers level up" do
        it "adds XP and increases level" do
          expect { profile.add_xp(80) }
            .to change(profile, :total_xp).from(50).to(130)
            .and change(profile, :level).from(1).to(2)
        end
        
        it "updates capabilities" do
          profile.add_xp(80)
          expect(profile.current_level_capabilities).to include("team_creation", "mentoring")
        end
        
        it "adds achievement" do
          expect { profile.add_xp(80) }
            .to change { profile.achievements.count }.by(1)
        end
      end
    end
    
    describe "#progress_to_next_level" do
      context "at level 1 with 50 XP" do
        let(:profile) { create(:volunteer_profile, level: 1, total_xp: 50) }
        
        it "returns correct progress percentage" do
          expect(profile.progress_to_next_level).to eq(50.0)
        end
      end
      
      context "at max level" do
        let(:profile) { create(:volunteer_profile, :level_3) }
        
        it "returns 100%" do
          expect(profile.progress_to_next_level).to eq(100)
        end
      end
    end
    
    describe "#can_access_capability?" do
      let(:profile) { create(:volunteer_profile, :level_2) }
      
      it "returns true for unlocked capabilities" do
        expect(profile.can_access_capability?("team_creation")).to be true
      end
      
      it "returns false for locked capabilities" do
        expect(profile.can_access_capability?("advanced_tasks")).to be false
      end
    end
  end
end

# spec/models/decidim/volunteer_scheduler/referral_spec.rb
require "rails_helper"

module Decidim::VolunteerScheduler
  RSpec.describe Referral, type: :model do
    describe ".create_referral_chain" do
      let(:level_1_user) { create(:user, :confirmed) }
      let(:level_2_user) { create(:user, :confirmed) }
      let(:level_3_user) { create(:user, :confirmed) }
      let(:new_user) { create(:user, :confirmed) }
      
      before do
        create(:volunteer_profile, user: level_1_user)
        create(:volunteer_profile, user: level_2_user, referrer: level_1_user)
        create(:volunteer_profile, user: level_3_user, referrer: level_2_user)
      end
      
      it "creates referral chain up to 5 levels" do
        expect { 
          described_class.create_referral_chain(level_3_user, new_user) 
        }.to change(Referral, :count).by(3)
      end
      
      it "sets correct commission rates" do
        described_class.create_referral_chain(level_3_user, new_user)
        
        referrals = Referral.where(referred: new_user).order(:level)
        expect(referrals.map(&:commission_rate)).to eq([0.10, 0.08, 0.06])
      end
      
      it "creates referrals in correct order" do
        described_class.create_referral_chain(level_3_user, new_user)
        
        referrals = Referral.where(referred: new_user).order(:level)
        expect(referrals.map(&:referrer)).to eq([level_3_user, level_2_user, level_1_user])
      end
    end
  end
end
```

### 10.3 Integration and System Tests
```ruby
# spec/system/decidim/volunteer_scheduler/volunteer_dashboard_spec.rb
require "rails_helper"

describe "Volunteer Dashboard", type: :system do
  let(:organization) { create(:organization) }
  let(:participatory_process) { create(:participatory_process, organization: organization) }
  let(:component) { create(:volunteer_scheduler_component, participatory_space: participatory_process) }
  let(:user) { create(:user, :confirmed, organization: organization) }
  let!(:volunteer_profile) { create(:volunteer_profile, user: user) }
  
  before do
    switch_to_host(organization.host)
    login_as user, scope: :user
  end
  
  describe "accessing the dashboard" do
    it "shows volunteer statistics" do
      visit decidim_volunteer_scheduler.root_path
      
      expect(page).to have_content("Volunteer Dashboard")
      expect(page).to have_content("Level #{volunteer_profile.level}")
      expect(page).to have_content("#{volunteer_profile.total_xp} XP")
      expect(page).to have_content("Referral Code: #{volunteer_profile.referral_code}")
    end
    
    it "displays available tasks" do
      task_template = create(:task_template, :level_1, component: component)
      
      visit decidim_volunteer_scheduler.root_path
      
      expect(page).to have_content(translated(task_template.title))
      expect(page).to have_button("Accept Task")
    end
    
    it "shows progress to next level" do
      volunteer_profile.update!(total_xp: 50)
      
      visit decidim_volunteer_scheduler.root_path
      
      expect(page).to have_css(".progress-bar[data-progress='50']")
      expect(page).to have_content("50 XP until next level")
    end
  end
  
  describe "task acceptance workflow" do
    let!(:task_template) { create(:task_template, :level_1, component: component) }
    
    it "allows accepting available tasks" do
      visit decidim_volunteer_scheduler.root_path
      
      within "[data-task-id='#{task_template.id}']" do
        click_button "Accept Task"
      end
      
      expect(page).to have_content("Task accepted successfully")
      expect(page).to have_content("My Assignments")
      
      assignment = user.task_assignments.last
      expect(assignment.task_template).to eq(task_template)
      expect(assignment.status).to eq("pending")
    end
    
    it "prevents accepting tasks above user level" do
      task_template.update!(level: 3)
      
      visit decidim_volunteer_scheduler.root_path
      
      expect(page).not_to have_button("Accept Task")
      expect(page).to have_content("Requires Level 3")
    end
  end
  
  describe "referral system" do
    it "displays referral link and allows copying" do
      visit decidim_volunteer_scheduler.root_path
      
      expect(page).to have_content("Your Referral Link")
      expect(page).to have_field("referral-link", with: user.referral_link)
      
      click_button "Copy Link"
      expect(page).to have_content("Copied!")
    end
    
    it "shows referral statistics" do
      referred_user = create(:user, :confirmed, organization: organization)
      create(:volunteer_profile, user: referred_user, referrer: user)
      
      visit decidim_volunteer_scheduler.root_path
      
      expect(page).to have_content("Referrals: 1")
      expect(page).to have_content("Commission Earned")
    end
  end
end

# spec/system/decidim/volunteer_scheduler/task_management_spec.rb
require "rails_helper"

describe "Task Management", type: :system do
  let(:organization) { create(:organization) }
  let(:participatory_process) { create(:participatory_process, organization: organization) }
  let(:component) { create(:volunteer_scheduler_component, participatory_space: participatory_process) }
  let(:user) { create(:user, :confirmed, organization: organization) }
  let!(:volunteer_profile) { create(:volunteer_profile, user: user) }
  let!(:assignment) { create(:task_assignment, :in_progress, assignee: user) }
  
  before do
    switch_to_host(organization.host)
    login_as user, scope: :user
  end
  
  describe "completing a task" do
    it "allows submitting task report" do
      visit decidim_volunteer_scheduler.assignment_path(assignment)
      
      fill_in "Report", with: "Task completed successfully with all requirements met."
      click_button "Submit Task"
      
      expect(page).to have_content("Task submitted for review")
      
      assignment.reload
      expect(assignment.status).to eq("submitted")
      expect(assignment.report).to be_present
    end
    
    it "updates XP and level when task is approved", :js do
      assignment.update!(status: :submitted, report: "Completed task")
      
      visit decidim_volunteer_scheduler.assignment_path(assignment)
      
      # Simulate admin approval
      assignment.update!(status: :completed, xp_earned: 50, completed_at: Time.current)
      volunteer_profile.add_xp(50)
      
      visit decidim_volunteer_scheduler.root_path
      
      expect(page).to have_content("50 XP")
      expect(page).to have_content("Task Completed!")
    end
  end
end
```

### 10.4 Performance and Load Testing
```ruby
# spec/performance/decidim/volunteer_scheduler/referral_commission_spec.rb
require "rails_helper"

describe "Referral Commission Performance", type: :performance do
  describe "commission calculation with large referral chains" do
    let(:organization) { create(:organization) }
    
    before do
      # Create a 5-level referral chain with 100 users at each level
      @root_user = create(:user, :confirmed, organization: organization)
      create(:volunteer_profile, user: @root_user)
      
      current_referrers = [@root_user]
      
      5.times do |level|
        next_level_users = []
        
        current_referrers.each do |referrer|
          20.times do
            referred = create(:user, :confirmed, organization: organization)
            create(:volunteer_profile, user: referred, referrer: referrer)
            next_level_users << referred
          end
        end
        
        current_referrers = next_level_users
      end
    end
    
    it "processes commission distribution efficiently" do
      leaf_user = @root_user.volunteer_profile.referrals_made.last.referred
      
      expect {
        Decidim::VolunteerScheduler::ReferralCommissionJob.perform_now(leaf_user.id, 100.0)
      }.to perform_under(2.seconds)
    end
    
    it "handles concurrent commission calculations" do
      leaf_users = Decidim::User.joins(:volunteer_profile)
                                .where.not(volunteer_profiles: { referrer_id: nil })
                                .limit(10)
      
      expect {
        threads = leaf_users.map do |user|
          Thread.new do
            Decidim::VolunteerScheduler::ReferralCommissionJob.perform_now(user.id, 50.0)
          end
        end
        threads.each(&:join)
      }.to perform_under(5.seconds)
    end
  end
end
```

## 11. Deployment Considerations

### 11.1 Migration Strategy
- Gradual rollout with feature flags
- Data migration scripts for existing users
- Rollback procedures for failed deployments

### 11.2 Monitoring
- Application performance monitoring
- Commission calculation accuracy tracking
- User engagement metrics
- Error tracking and alerting

This technical specification provides a comprehensive blueprint for implementing the Decidim Volunteer Scheduler module while following Decidim's architectural patterns and best practices.