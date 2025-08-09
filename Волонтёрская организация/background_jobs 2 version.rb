# app/jobs/decidim/volunteer_scheduler/application_job.rb
module Decidim
  module VolunteerScheduler
    class ApplicationJob < ActiveJob::Base
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
        
        # Send error notification to monitoring system if available
        if defined?(Sentry)
          Sentry.capture_exception(e, extra: { job_name: self.class.name, arguments: arguments })
        end
        
        raise e
      end
    end
  end
end

# app/jobs/decidim/volunteer_scheduler/referral_commission_job.rb
module Decidim
  module VolunteerScheduler
    class ReferralCommissionJob < ApplicationJob
      queue_as :high_priority
      
      def perform(user_id, scicent_amount, source_type = "task_completion")
        with_error_handling do
          user = Decidim::User.find(user_id)
          referrals = Referral.active.where(referred: user).includes(:referrer)
          
          return if referrals.empty? || scicent_amount <= 0
          
          total_distributed = 0
          
          Referral.transaction do
            referrals.each do |referral|
              commission_amount = referral.add_commission(scicent_amount)
              total_distributed += commission_amount
              
              Rails.logger.info "Distributed #{commission_amount} SCT commission to user #{referral.referrer_id} " \
                               "from #{user.name}'s #{source_type} (Level #{referral.level})"
            end
          end
          
          # Update activity multipliers for all affected users
          affected_user_ids = referrals.pluck(:referrer_id) + [user_id]
          affected_user_ids.uniq.each do |affected_user_id|
            RecalculateActivityMultiplierJob.perform_later(affected_user_id)
          end
          
          Rails.logger.info "Total commission distributed: #{total_distributed} SCT for #{source_type}"
          total_distributed
        end
      end
    end
  end
end

# app/jobs/decidim/volunteer_scheduler/recalculate_activity_multiplier_job.rb
module Decidim
  module VolunteerScheduler
    class RecalculateActivityMultiplierJob < ApplicationJob
      queue_as :medium_priority
      
      def perform(user_id)
        with_error_handling do
          user = Decidim::User.find(user_id)
          profile = user.volunteer_profile
          
          return unless profile
          
          old_multiplier = profile.activity_multiplier
          new_multiplier = profile.calculate_activity_multiplier
          
          if (old_multiplier - new_multiplier).abs > 0.01 # Only update if significant change
            profile.update!(activity_multiplier: new_multiplier)
            
            Rails.logger.info "Updated activity multiplier for user #{user_id}: " \
                             "#{old_multiplier} -> #{new_multiplier}"
            
            # Trigger event if multiplier increased significantly
            if new_multiplier > old_multiplier + 0.1
              trigger_multiplier_boost_event(user, old_multiplier, new_multiplier)
            end
          end
        end
      end
      
      private
      
      def trigger_multiplier_boost_event(user, old_multiplier, new_multiplier)
        Decidim::EventsManager.publish(
          event: "decidim.volunteer_scheduler.multiplier_boost",
          event_class: "Decidim::VolunteerScheduler::MultiplierBoostEvent",
          resource: user.volunteer_profile,
          affected_users: [user],
          extra: {
            old_multiplier: old_multiplier,
            new_multiplier: new_multiplier,
            boost_amount: new_multiplier - old_multiplier
          }
        )
      end
    end
  end
end

# app/jobs/decidim/volunteer_scheduler/level_up_notification_job.rb
module Decidim
  module VolunteerScheduler
    class LevelUpNotificationJob < ApplicationJob
      queue_as :low_priority
      
      def perform(user_id, old_level = nil, new_level = nil)
        with_error_handling do
          user = Decidim::User.find(user_id)
          profile = user.volunteer_profile
          
          return unless profile
          
          # If levels not provided, use current profile data
          new_level ||= profile.level
          old_level ||= new_level - 1
          
          # Send notification
          Decidim::EventsManager.publish(
            event: "decidim.volunteer_scheduler.level_up",
            event_class: "Decidim::VolunteerScheduler::LevelUpEvent",
            resource: profile,
            affected_users: [user],
            extra: {
              old_level: old_level,
              new_level: new_level,
              new_capabilities: unlock_message(new_level)
            }
          )
          
          # Recalculate activity multiplier due to level change
          RecalculateActivityMultiplierJob.perform_later(user_id)
          
          Rails.logger.info "Level up notification sent to user #{user_id}: Level #{old_level} -> #{new_level}"
        end
      end
      
      private
      
      def unlock_message(level)
        capabilities = VolunteerProfile::LEVEL_CAPABILITIES[level] || []
        I18n.t("decidim.volunteer_scheduler.notifications.level_up.capabilities", 
               capabilities: capabilities.join(", "))
      end
    end
  end
end

# app/jobs/decidim/volunteer_scheduler/daily_assignment_reminder_job.rb
module Decidim
  module VolunteerScheduler
    class DailyAssignmentReminderJob < ApplicationJob
      queue_as :scheduled
      
      def perform
        with_error_handling do
          # Find assignments due soon
          due_soon_assignments = TaskAssignment.due_soon.includes(:assignee, :task_template)
          
          # Find overdue assignments
          overdue_assignments = TaskAssignment.overdue.includes(:assignee, :task_template)
          
          # Send due soon reminders
          due_soon_assignments.find_each do |assignment|
            send_due_soon_reminder(assignment)
          end
          
          # Send overdue reminders
          overdue_assignments.find_each do |assignment|
            send_overdue_reminder(assignment)
          end
          
          Rails.logger.info "Sent #{due_soon_assignments.count} due soon and #{overdue_assignments.count} overdue reminders"
        end
      end
      
      private
      
      def send_due_soon_reminder(assignment)
        Decidim::EventsManager.publish(
          event: "decidim.volunteer_scheduler.task_due_soon",
          event_class: "Decidim::VolunteerScheduler::TaskDueSoonEvent",
          resource: assignment,
          affected_users: [assignment.assignee],
          extra: {
            days_until_due: assignment.days_until_due,
            due_date: assignment.due_date
          }
        )
      end
      
      def send_overdue_reminder(assignment)
        Decidim::EventsManager.publish(
          event: "decidim.volunteer_scheduler.task_overdue",
          event_class: "Decidim::VolunteerScheduler::TaskOverdueEvent",
          resource: assignment,
          affected_users: [assignment.assignee],
          extra: {
            days_overdue: (Time.current.to_date - assignment.due_date.to_date).to_i
          }
        )
      end
    end
  end
end

# app/jobs/decidim/volunteer_scheduler/create_default_templates_job.rb
module Decidim
  module VolunteerScheduler
    class CreateDefaultTemplatesJob < ApplicationJob
      queue_as :low_priority
      
      def perform(component_id)
        with_error_handling do
          component = Decidim::Component.find(component_id)
          organization = component.organization
          
          # Create default templates for each level
          create_level_1_templates(component, organization)
          create_level_2_templates(component, organization)
          create_level_3_templates(component, organization)
          
          Rails.logger.info "Created default templates for component #{component_id}"
        end
      end
      
      private
      
      def create_level_1_templates(component, organization)
        locales = organization.available_locales
        
        # Basic outreach task
        TaskTemplate.create!(
          component: component,
          title: build_localized_attribute(locales, "Share on Social Media"),
          description: build_localized_attribute(locales, "Share our campaign message on your social media platforms and engage with followers."),
          level: 1,
          frequency: :weekly,
          category: :outreach,
          xp_reward: 15,
          scicent_reward: 5.0,
          active: true
        )
        
        # Basic administrative task
        TaskTemplate.create!(
          component: component,
          title: build_localized_attribute(locales, "Data Entry"),
          description: build_localized_attribute(locales, "Help maintain our volunteer database by entering contact information and updating records."),
          level: 1,
          frequency: :daily,
          category: :administrative,
          xp_reward: 10,
          scicent_reward: 3.0,
          active: true
        )
      end
      
      def create_level_2_templates(component, organization)
        locales = organization.available_locales
        
        # Team coordination task
        TaskTemplate.create!(
          component: component,
          title: build_localized_attribute(locales, "Coordinate Local Team"),
          description: build_localized_attribute(locales, "Organize and coordinate activities for your local volunteer team."),
          level: 2,
          frequency: :weekly,
          category: :administrative,
          xp_reward: 30,
          scicent_reward: 15.0,
          active: true,
          requirements: { required_capabilities: ["team_creation"] }.to_json
        )
        
        # Mentoring task
        TaskTemplate.create!(
          component: component,
          title: build_localized_attribute(locales, "Mentor New Volunteers"),
          description: build_localized_attribute(locales, "Guide and support new volunteers in their first tasks."),
          level: 2,
          frequency: :monthly,
          category: :mentoring,
          xp_reward: 50,
          scicent_reward: 25.0,
          active: true,
          requirements: { required_capabilities: ["mentoring"] }.to_json
        )
      end
      
      def create_level_3_templates(component, organization)
        locales = organization.available_locales
        
        # Advanced leadership task
        TaskTemplate.create!(
          component: component,
          title: build_localized_attribute(locales, "Lead Campaign Strategy"),
          description: build_localized_attribute(locales, "Develop and implement strategic campaign initiatives in your region."),
          level: 3,
          frequency: :monthly,
          category: :administrative,
          xp_reward: 100,
          scicent_reward: 50.0,
          active: true,
          requirements: { 
            required_capabilities: ["team_leadership", "advanced_tasks"],
            min_completed_tasks: 20,
            min_xp: 300
          }.to_json
        )
      end
      
      def build_localized_attribute(locales, text)
        locales.each_with_object({}) do |locale, hash|
          hash[locale.to_s] = text
        end
      end
    end
  end
end

# app/jobs/decidim/volunteer_scheduler/cleanup_component_data_job.rb
module Decidim
  module VolunteerScheduler
    class CleanupComponentDataJob < ApplicationJob
      queue_as :low_priority
      
      def perform(component_id)
        with_error_handling do
          # Find all task templates for this component
          task_templates = TaskTemplate.where(decidim_component_id: component_id)
          
          # Cancel all pending/in-progress assignments
          TaskAssignment.joins(:task_template)
                       .where(decidim_volunteer_scheduler_task_templates: { decidim_component_id: component_id })
                       .where(status: [:pending, :in_progress, :submitted])
                       .find_each do |assignment|
            assignment.cancel_task!("Component removed")
          end
          
          # Clean up the templates (assignments will be cascade deleted)
          task_templates.destroy_all
          
          Rails.logger.info "Cleaned up data for component #{component_id}"
        end
      end
    end
  end
end

# config/schedule.rb (for whenever gem - optional)
# This would be added to the main application, not the module
# 
# every 1.day, at: '9:00 am' do
#   runner "Decidim::VolunteerScheduler::DailyAssignmentReminderJob.perform_later"
# end
# 
# every 1.hour do
#   runner "Decidim::VolunteerScheduler::RecalculateActivityMultiplierJob.perform_later" 
# end