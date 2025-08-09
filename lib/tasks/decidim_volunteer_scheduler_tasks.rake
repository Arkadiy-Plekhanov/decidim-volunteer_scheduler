# frozen_string_literal: true

namespace :decidim_volunteer_scheduler do
  namespace :install do
    desc "Install decidim_volunteer_scheduler migrations"
    task :migrations do
      puts "Installing Volunteer Scheduler migrations..."
      
      # Get the Rails application
      rails_app = Rails.application
      
      # Get source migrations path
      source = File.expand_path("../../db/migrate", __dir__)
      
      # Get destination path
      destination = rails_app.root.join("db/migrate")
      
      # Get migration files
      migrations = Dir.glob("#{source}/*.rb")
      
      migrations.each do |migration|
        filename = File.basename(migration)
        
        # Skip if migration already exists
        existing = Dir.glob("#{destination}/*_#{filename.split('_', 2).last}")
        if existing.any?
          puts "  Skipping #{filename} (already exists)"
          next
        end
        
        # Generate new timestamp
        timestamp = Time.now.utc.strftime("%Y%m%d%H%M%S").to_i
        
        # Ensure unique timestamp
        while File.exist?("#{destination}/#{timestamp}_#{filename.split('_', 2).last}")
          timestamp += 1
        end
        
        # Copy migration with new timestamp
        new_filename = "#{timestamp}_#{filename.split('_', 2).last}"
        new_path = "#{destination}/#{new_filename}"
        
        FileUtils.cp(migration, new_path)
        puts "  Copied #{filename} -> #{new_filename}"
      end
      
      puts "✅ Migrations installed successfully!"
      puts "Run 'rails db:migrate' to apply them."
    end
  end
  
  desc "Run scheduled jobs for volunteer scheduler"
  task scheduled_jobs: :environment do
    puts "Running scheduled jobs for Volunteer Scheduler..."
    
    # Update activity multipliers for all active volunteers
    Decidim::VolunteerScheduler::VolunteerProfile
      .joins(:user)
      .where(users: { deleted_at: nil, blocked_at: nil })
      .where("updated_at < ?", 1.day.ago)
      .find_each do |profile|
        Decidim::VolunteerScheduler::ActivityMultiplierJob.perform_later(profile.id)
      end
    
    # Process pending referral commissions
    Decidim::VolunteerScheduler::ScicentTransaction
      .pending
      .where("created_at < ?", 1.hour.ago)
      .find_each do |transaction|
        Decidim::VolunteerScheduler::ReferralCommissionJob.perform_later(transaction.id)
      end
    
    # Send task reminders
    Decidim::VolunteerScheduler::TaskAssignment
      .pending
      .where("due_date <= ?", 1.day.from_now)
      .where("due_date > ?", Time.current)
      .find_each do |assignment|
        Decidim::VolunteerScheduler::TaskReminderJob.perform_later(assignment.id)
      end
    
    puts "✅ Scheduled jobs queued successfully!"
  end
  
  desc "Clean up old data"
  task cleanup: :environment do
    puts "Cleaning up old Volunteer Scheduler data..."
    
    # Archive old completed assignments (> 6 months)
    old_assignments = Decidim::VolunteerScheduler::TaskAssignment
                       .where(status: :approved)
                       .where("reviewed_at < ?", 6.months.ago)
    
    puts "  Archiving #{old_assignments.count} old assignments..."
    old_assignments.update_all(archived: true, archived_at: Time.current)
    
    # Clean up orphaned records
    orphaned_profiles = Decidim::VolunteerScheduler::VolunteerProfile
                         .left_joins(:user)
                         .where(users: { id: nil })
    
    puts "  Removing #{orphaned_profiles.count} orphaned profiles..."
    orphaned_profiles.destroy_all
    
    puts "✅ Cleanup complete!"
  end
  
  desc "Generate performance report"
  task report: :environment do
    puts "\n📊 Volunteer Scheduler Performance Report"
    puts "=" * 50
    
    # Overall stats
    total_volunteers = Decidim::VolunteerScheduler::VolunteerProfile.count
    active_volunteers = Decidim::VolunteerScheduler::VolunteerProfile
                         .joins(:task_assignments)
                         .where(task_assignments: { status: [:pending, :submitted] })
                         .distinct
                         .count
    
    total_tasks = Decidim::VolunteerScheduler::TaskAssignment.count
    completed_tasks = Decidim::VolunteerScheduler::TaskAssignment.approved.count
    
    puts "\n📈 Overall Statistics:"
    puts "  Total Volunteers: #{total_volunteers}"
    puts "  Active Volunteers: #{active_volunteers}"
    puts "  Total Tasks: #{total_tasks}"
    puts "  Completed Tasks: #{completed_tasks}"
    puts "  Completion Rate: #{(completed_tasks.to_f / total_tasks * 100).round(2)}%" if total_tasks > 0
    
    # Level distribution
    puts "\n🎮 Level Distribution:"
    Decidim::VolunteerScheduler::VolunteerProfile
      .group(:level)
      .count
      .each do |level, count|
        puts "  Level #{level}: #{count} volunteers"
      end
    
    # Top volunteers
    puts "\n🏆 Top 5 Volunteers (by XP):"
    Decidim::VolunteerScheduler::VolunteerProfile
      .joins(:user)
      .order(total_xp: :desc)
      .limit(5)
      .each_with_index do |profile, index|
        puts "  #{index + 1}. #{profile.user.name}: #{profile.total_xp} XP (Level #{profile.level})"
      end
    
    # Task categories
    puts "\n📋 Tasks by Category:"
    Decidim::VolunteerScheduler::TaskTemplate
      .group(:category)
      .count
      .each do |category, count|
        puts "  #{category.humanize}: #{count} templates"
      end
    
    # Referral stats
    total_referrals = Decidim::VolunteerScheduler::Referral.count
    active_referrals = Decidim::VolunteerScheduler::Referral.active.count
    
    puts "\n🔗 Referral System:"
    puts "  Total Referrals: #{total_referrals}"
    puts "  Active Referrals: #{active_referrals}"
    
    puts "\n" + "=" * 50
    puts "Report generated at: #{Time.current}"
  end
  
  desc "Reset volunteer XP and levels (DANGEROUS!)"
  task reset_xp: :environment do
    puts "⚠️  WARNING: This will reset all volunteer XP and levels!"
    puts "Are you sure? Type 'RESET' to confirm:"
    
    input = STDIN.gets.chomp
    
    if input == "RESET"
      Decidim::VolunteerScheduler::VolunteerProfile.update_all(
        total_xp: 0,
        level: 1,
        activity_multiplier: 1.0
      )
      puts "✅ All volunteer XP and levels have been reset."
    else
      puts "❌ Reset cancelled."
    end
  end
end

# Cron job tasks for whenever gem (if used)
namespace :decidim_volunteer_scheduler do
  namespace :cron do
    desc "Daily maintenance tasks"
    task daily: :environment do
      Rake::Task["decidim_volunteer_scheduler:scheduled_jobs"].invoke
      Rake::Task["decidim_volunteer_scheduler:cleanup"].invoke
    end
    
    desc "Weekly report generation"
    task weekly: :environment do
      Rake::Task["decidim_volunteer_scheduler:report"].invoke
    end
  end
end