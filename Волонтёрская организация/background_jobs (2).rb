# app/jobs/decidim/volunteer_scheduler/application_job.rb
module Decidim
  module VolunteerScheduler
    class ApplicationJob < ActiveJob::Base
      queue_as :volunteer_scheduler
      
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
      
      def perform(user_id, scicent_amount)
        with_error_handling do
          user = Decidim::User.find(user_id)
          referrals = Referral.active.where(referred: user).includes(:referrer)
          
          total_distributed = 0
          
          Rails.logger.info "Processing referral commissions for user #{user_id}, amount: #{scicent_amount}"
          
          Referral.transaction do
            referrals.each do |referral|
              commission_amount = referral.add_commission(scicent_amount)
              total_distributed += commission_amount
              
              Rails.logger.debug "Distributed #{commission_amount} SCT to referrer #{referral.referrer_id} (Level #{referral.level})"
              
              # Update referrer's activity multiplier due to successful referral activity
              RecalculateActivityMultiplierJob.perform_later(referral.referrer_id)
            end
          end
          
          Rails.logger.info "Total distributed: #{total_distributed} SCT across #{referrals.count} referrals"
          
          # Update user's last activity to keep referral chain active
          user.volunteer_profile&.update_column(:last_activity_at, Time.current)
          
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
          
          Rails.logger.debug "Recalculating activity multiplier for user #{user_id}"
          
          old_multiplier = profile.activity_multiplier
          new_multiplier = profile.calculate_activity_multiplier
          
          if (old_multiplier - new_multiplier).abs > 0.01 # Only update if significant change
            profile.update_column(:activity_multiplier, new_multiplier)
            
            Rails.logger.info "Updated activity multiplier for user #{user_id}: #{old_multiplier} -> #{new_multiplier}"
            
            # Trigger event if multiplier increased significantly
            if new_multiplier > old_multiplier + 0.1
              trigger_multiplier_boost_event(user, old_multiplier, new_multiplier)
            end
          end
          
          new_multiplier
        end
      end
      
      private
      
      def trigger_multiplier_boost_event(user, old_multiplier, new_multiplier)
        Decidim::EventsManager.publish(
          event: "decidim.volunteer_scheduler.activity_multiplier_boost",
          event_class: "Decidim::VolunteerScheduler::ActivityMultiplierBoostEvent",
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
      
      def perform(user_id)
        with_error_handling do
          user = Decidim::User.find(user_id)
          profile = user.volunteer_profile
          
          return unless profile
          
          Rails.logger.info "Processing level up notification for user #{user_id}, level: #{profile.level}"
          
          # Send notification through Decidim's notification system
          Decidim::EventsManager.publish(
            event: "decidim.volunteer_scheduler.level_up",
            event_class: "Decidim::VolunteerScheduler::LevelUpEvent",
            resource: profile,
            affected_users: [user],
            extra: {
              new_level: profile.level,
              new_capabilities: profile.current_capabilities,
              total_xp: profile.total_xp
            }
          )
          
          # Also trigger activity multiplier recalculation
          RecalculateActivityMultiplierJob.perform_later(user_id)
        end
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
          Rails.logger.info "Running daily assignment reminders"
          
          # Find assignments due soon
          due_soon_assignments = TaskAssignment.due_soon.includes(:assignee, :task_template)
          
          Rails.logger.info "Found #{due_soon_assignments.count} assignments due soon"
          
          due_soon_assignments.find_each do |assignment|
            send_due_soon_reminder(assignment)
          end
          
          # Find overdue assignments
          overdue_assignments = TaskAssignment.overdue.includes(:assignee, :task_template)
          
          Rails.logger.info "Found #{overdue_assignments.count} overdue assignments"
          
          overdue_assignments.find_each do |assignment|
            send_overdue_reminder(assignment)
          end
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
            days_remaining: assignment.days_until_due,
            task_title: assignment.task_template.title
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
            days_overdue: (Time.current - assignment.due_date).to_i / 1.day,
            task_title: assignment.task_template.title
          }
        )
      end
    end
  end
end

# app/jobs/decidim/volunteer_scheduler/weekly_reports_job.rb
module Decidim
  module VolunteerScheduler
    class WeeklyReportsJob < ApplicationJob
      queue_as :scheduled
      
      def perform
        with_error_handling do
          Rails.logger.info "Generating weekly volunteer reports"
          
          week_start = 1.week.ago.beginning_of_week
          week_end = week_start.end_of_week
          
          # Generate organization-level reports
          Decidim::Organization.find_each do |organization|
            generate_organization_report(organization, week_start, week_end)
          end
        end
      end
      
      private
      
      def generate_organization_report(organization, week_start, week_end)
        volunteer_profiles = VolunteerProfile.joins(:user)
                                           .where(decidim_users: { decidim_organization_id: organization.id })
        
        report_data = {
          organization: organization.name,
          period: "#{week_start.strftime('%Y-%m-%d')} to #{week_end.strftime('%Y-%m-%d')}",
          total_volunteers: volunteer_profiles.count,
          new_volunteers: volunteer_profiles.where(created_at: week_start..week_end).count,
          active_volunteers: volunteer_profiles.where("last_activity_at >= ?", week_start).count,
          tasks_completed: TaskAssignment.joins(assignee: :organization)
                                        .where(decidim_users: { decidim_organization_id: organization.id })
                                        .where(status: :completed, completed_at: week_start..week_end)
                                        .count,
          scicent_distributed: ScicentTransaction.joins(user: :organization)
                                               .where(decidim_users: { decidim_organization_id: organization.id })
                                               .where(status: :completed, created_at: week_start..week_end)
                                               .sum(:amount),
          referrals_created: Referral.joins(referred: :organization)
                                   .where(decidim_users: { decidim_organization_id: organization.id })
                                   .where(created_at: week_start..week_end)
                                   .count
        }
        
        Rails.logger.info "Weekly report for #{organization.name}: #{report_data}"
        
        # Send report to admins if needed
        send_weekly_report_to_admins(organization, report_data)
      end
      
      def send_weekly_report_to_admins(organization, report_data)
        # This could be expanded to send actual email reports
        admins = organization.admins
        
        Decidim::EventsManager.publish(
          event: "decidim.volunteer_scheduler.weekly_report",
          event_class: "Decidim::VolunteerScheduler::WeeklyReportEvent",
          resource: organization,
          affected_users: admins,
          extra: report_data
        )
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
          Rails.logger.info "Cleaning up data for component #{component_id}"
          
          # Clean up task templates and their assignments
          task_templates = TaskTemplate.where(decidim_component_id: component_id)
          assignment_count = TaskAssignment.joins(:task_template)
                                          .where(decidim_volunteer_scheduler_task_templates: { decidim_component_id: component_id })
                                          .count
          
          Rails.logger.info "Removing #{task_templates.count} task templates and #{assignment_count} assignments"
          
          TaskTemplate.transaction do
            task_templates.destroy_all
          end
          
          Rails.logger.info "Component cleanup completed for component #{component_id}"
        end
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
          
          Rails.logger.info "Creating default templates for component #{component_id}"
          
          # Create basic templates for each level
          default_templates = [
            {
              title: { en: "Social Media Outreach", es: "Alcance en Redes Sociales" },
              description: { en: "Share party content on social media platforms", es: "Compartir contenido del partido en plataformas de redes sociales" },
              level: 1,
              category: :outreach,
              frequency: :daily,
              xp_reward: 10,
              scicent_reward: 5.0
            },
            {
              title: { en: "Community Event Support", es: "Apoyo a Eventos Comunitarios" },
              description: { en: "Help organize and support local community events", es: "Ayudar a organizar y apoyar eventos comunitarios locales" },
              level: 2,
              category: :administrative,
              frequency: :weekly,
              xp_reward: 25,
              scicent_reward: 15.0
            },
            {
              title: { en: "Policy Research and Analysis", es: "Investigación y Análisis de Políticas" },
              description: { en: "Research and analyze policy proposals and their implications", es: "Investigar y analizar propuestas de políticas y sus implicaciones" },
              level: 3,
              category: :research,
              frequency: :monthly,
              xp_reward: 100,
              scicent_reward: 50.0
            }
          ]
          
          default_templates.each do |template_data|
            TaskTemplate.create!(
              component: component,
              title: template_data[:title],
              description: template_data[:description],
              level: template_data[:level],
              category: template_data[:category],
              frequency: template_data[:frequency],
              xp_reward: template_data[:xp_reward],
              scicent_reward: template_data[:scicent_reward],
              active: true
            )
          end
          
          Rails.logger.info "Created #{default_templates.count} default templates for component #{component_id}"
        end
      end
    end
  end
end