# lib/decidim/volunteer_scheduler/component.rb
require "decidim/components/namer"

Decidim.register_component(:volunteer_scheduler) do |component|
  component.engine = Decidim::VolunteerScheduler::Engine
  component.admin_engine = Decidim::VolunteerScheduler::AdminEngine
  component.icon = "decidim/volunteer_scheduler/icon.svg"
  component.name = "volunteer_scheduler"
  component.permissions_class_name = "Decidim::VolunteerScheduler::Permissions"
  
  # Lifecycle hooks
  component.on(:create) do |component_instance|
    Decidim::VolunteerScheduler::CreateDefaultTemplatesJob.perform_later(component_instance.id)
  end
  
  component.on(:destroy) do |component_instance|
    Decidim::VolunteerScheduler::CleanupComponentDataJob.perform_later(component_instance.id)
  end
  
  # Global settings (persistent across all steps)
  component.settings(:global) do |settings|
    settings.attribute :enable_referral_system, type: :boolean, default: true
    settings.attribute :max_referral_levels, type: :integer, default: 5
    settings.attribute :enable_teams, type: :boolean, default: true
    settings.attribute :scicent_token_enabled, type: :boolean, default: true
    settings.attribute :default_xp_reward, type: :integer, default: 10
    settings.attribute :enable_activity_multiplier, type: :boolean, default: true
    settings.attribute :max_activity_multiplier, type: :text, default: "3.0"
    settings.attribute :enable_mentoring, type: :boolean, default: true
    settings.attribute :auto_create_profiles, type: :boolean, default: true
    settings.attribute :public_leaderboard, type: :boolean, default: false
  end
  
  # Step-specific settings (can change between participatory process steps)
  component.settings(:step) do |settings|
    settings.attribute :task_creation_enabled, type: :boolean, default: true
    settings.attribute :assignment_deadline_days, type: :integer, default: 7
    settings.attribute :max_concurrent_assignments, type: :integer, default: 3
    settings.attribute :enable_public_leaderboard, type: :boolean, default: false
    settings.attribute :commission_rate_modifier, type: :text, default: "1.0"
    settings.attribute :xp_multiplier_modifier, type: :text, default: "1.0"
  end
  
  # Data export capabilities
  component.exports :task_assignments do |exports|
    exports.collection do |component_instance|
      Decidim::VolunteerScheduler::TaskAssignment
        .joins(:task_template)
        .where(decidim_volunteer_scheduler_task_templates: { 
          decidim_component_id: component_instance.id 
        })
    end
    exports.include_in_open_data = true
    exports.serializer Decidim::VolunteerScheduler::TaskAssignmentSerializer
  end
  
  component.exports :volunteer_profiles do |exports|
    exports.collection do |component_instance|
      # Export profiles of users who have interacted with this component
      user_ids = Decidim::VolunteerScheduler::TaskAssignment
                   .joins(:task_template)
                   .where(decidim_volunteer_scheduler_task_templates: { 
                     decidim_component_id: component_instance.id 
                   })
                   .distinct
                   .pluck(:assignee_id)
      
      Decidim::VolunteerScheduler::VolunteerProfile
        .where(user_id: user_ids)
    end
    exports.include_in_open_data = false # Privacy sensitive
    exports.serializer Decidim::VolunteerScheduler::VolunteerProfileSerializer
  end
  
  component.exports :referral_data do |exports|
    exports.collection do |component_instance|
      # Only export aggregated referral statistics, not personal data
      organization = component_instance.organization
      Decidim::VolunteerScheduler::Referral
        .joins(referrer: :organization)
        .where(decidim_users: { decidim_organization_id: organization.id })
        .select(:level, :active, :created_at) # Only non-personal fields
    end
    exports.include_in_open_data = false
    exports.serializer Decidim::VolunteerScheduler::ReferralStatsSerializer
  end
  
  # Data import capabilities  
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
      msg.set(:help) { 
        I18n.t("decidim.volunteer_scheduler.admin.imports.help.task_templates") 
      }
    end
    
    imports.creator Decidim::VolunteerScheduler::TaskTemplateCreator
    
    imports.example do |import_component|
      organization = import_component.organization
      locales = organization.available_locales
      
      headers = locales.map { |l| "title/#{l}" } + 
                locales.map { |l| "description/#{l}" } +
                %w[level frequency category xp_reward scicent_reward active requirements]
      
      sample_data = locales.map { "Sample Task Title" } + 
                    locales.map { "Detailed task description with requirements and instructions" } +
                    ["2", "weekly", "outreach", "50", "25.0", "true", "{}"]
      
      [headers, sample_data]
    end
  end
  
  # Sample data for development/testing
  component.seeds do |participatory_space|
    organization = participatory_space.organization
    
    component = Decidim::Component.create!(
      name: Decidim::Components::Namer.new(
        organization.available_locales,
        :volunteer_scheduler
      ).i18n_name,
      manifest_name: :volunteer_scheduler,
      published_at: Time.current,
      participatory_space: participatory_space,
      settings: {
        global: {
          enable_referral_system: true,
          enable_teams: true,
          scicent_token_enabled: true,
          enable_activity_multiplier: true
        }
      }
    )
    
    # Create sample task templates for each level and category
    levels = [1, 2, 3]
    categories = [:outreach, :technical, :administrative, :creative, :research]
    frequencies = [:weekly, :monthly, :one_time]
    
    levels.each do |level|
      categories.sample(2).each do |category|
        Decidim::VolunteerScheduler::TaskTemplate.create!(
          component: component,
          title: Decidim::Faker::Localized.sentence(word_count: 4),
          description: Decidim::Faker::Localized.wrapped("<p>", "</p>") do
            Decidim::Faker::Localized.paragraphs(number: 2).join(" ")
          end,
          level: level,
          frequency: frequencies.sample,
          category: category,
          xp_reward: level * 25 + rand(25),
          scicent_reward: level * 10.0 + rand(20.0),
          active: true,
          max_assignments: [nil, 5, 10, 20].sample
        )
      end
    end
  end
  
  # Statistics for admin dashboard
  component.stats.register :task_templates_count, priority: Decidim::StatsRegistry::HIGH_PRIORITY do |components|
    Decidim::VolunteerScheduler::TaskTemplate.where(component: components).count
  end
  
  component.stats.register :assignments_count, priority: Decidim::StatsRegistry::HIGH_PRIORITY do |components|
    Decidim::VolunteerScheduler::TaskAssignment
      .joins(:task_template)
      .where(decidim_volunteer_scheduler_task_templates: { decidim_component_id: components })
      .count
  end
  
  component.stats.register :completed_assignments_count, priority: Decidim::StatsRegistry::MEDIUM_PRIORITY do |components|
    Decidim::VolunteerScheduler::TaskAssignment
      .joins(:task_template)
      .where(decidim_volunteer_scheduler_task_templates: { decidim_component_id: components })
      .where(status: :completed)
      .count
  end
  
  component.stats.register :active_volunteers_count, priority: Decidim::StatsRegistry::MEDIUM_PRIORITY do |components|
    user_ids = Decidim::VolunteerScheduler::TaskAssignment
                 .joins(:task_template)
                 .where(decidim_volunteer_scheduler_task_templates: { decidim_component_id: components })
                 .where("assigned_at > ?", 3.months.ago)
                 .distinct
                 .pluck(:assignee_id)
    
    Decidim::VolunteerScheduler::VolunteerProfile.where(user_id: user_ids).count
  end
end

# app/models/concerns/decidim/volunteer_scheduler/user_extensions.rb
module Decidim
  module VolunteerScheduler
    module UserExtensions
      extend ActiveSupport::Concern
      
      included do
        has_one :volunteer_profile, 
                class_name: "Decidim::VolunteerScheduler::VolunteerProfile",
                dependent: :destroy
        
        has_many :task_assignments, 
                 class_name: "Decidim::VolunteerScheduler::TaskAssignment",
                 foreign_key: :assignee_id,
                 dependent: :destroy
                 
        has_many :referrals_made,
                 class_name: "Decidim::VolunteerScheduler::Referral",
                 foreign_key: :referrer_id,
                 dependent: :destroy
                 
        has_many :referrals_received,
                 class_name: "Decidim::VolunteerScheduler::Referral", 
                 foreign_key: :referred_id,
                 dependent: :destroy
                 
        has_many :scicent_transactions,
                 class_name: "Decidim::VolunteerScheduler::ScicentTransaction",
                 dependent: :destroy
        
        after_create :create_volunteer_profile_if_enabled
        before_destroy :cleanup_volunteer_data
      end
      
      def volunteer?
        volunteer_profile.present?
      end
      
      def volunteer_level
        volunteer_profile&.level || 1
      end
      
      def volunteer_xp
        volunteer_profile&.total_xp || 0
      end
      
      def volunteer_scicent_earned
        volunteer_profile&.total_scicent_earned || 0.0
      end
      
      def referral_link(component = nil)
        return nil unless volunteer_profile
        
        if component
          # Component-specific referral link
          decidim_volunteer_scheduler.root_url(
            host: organization.host,
            component_id: component.id,
            ref: volunteer_profile.referral_code
          )
        else
          # General registration referral link
          decidim.new_user_registration_url(
            host: organization.host,
            ref: volunteer_profile.referral_code
          )
        end
      end
      
      def can_access_volunteer_capability?(capability)
        volunteer_profile&.can_access_capability?(capability) || false
      end
      
      def active_task_assignments
        task_assignments.where(status: [:pending, :in_progress, :submitted])
      end
      
      def completed_task_assignments
        task_assignments.where(status: :completed)
      end
      
      def total_referral_commission
        volunteer_profile&.total_referral_commission || 0.0
      end
      
      def referral_tree_size
        referrals_received.active.count
      end
      
      def activity_multiplier
        volunteer_profile&.activity_multiplier || 1.0
      end
      
      def volunteer_statistics
        return {} unless volunteer_profile
        
        {
          level: volunteer_level,
          total_xp: volunteer_xp,
          tasks_completed: volunteer_profile.tasks_completed,
          scicent_earned: volunteer_scicent_earned,
          referrals_made: referrals_made.active.count,
          activity_multiplier: activity_multiplier,
          current_capabilities: volunteer_profile.current_capabilities
        }
      end
      
      private
      
      def create_volunteer_profile_if_enabled
        # Check if any volunteer scheduler component in the organization has auto-creation enabled
        volunteer_components = organization.published_components
                                         .where(manifest_name: "volunteer_scheduler")
        
        return unless volunteer_components.exists?
        
        auto_create_enabled = volunteer_components.any? do |component|
          component.settings.global["auto_create_profiles"]
        end
        
        if auto_create_enabled && confirmed?
          create_volunteer_profile_with_referral
        end
      end
      
      def create_volunteer_profile_with_referral
        # Check for referral code in session or params
        referral_code = extract_referral_code
        referrer = find_referrer(referral_code) if referral_code.present?
        
        profile = Decidim::VolunteerScheduler::VolunteerProfile.create!(
          user: self,
          referrer: referrer
        )
        
        # Create referral chain if referrer exists
        if referrer
          Decidim::VolunteerScheduler::Referral.create_referral_chain(referrer, self)
        end
        
        profile
      end
      
      def extract_referral_code
        # This would typically be extracted from session, params, or cookies
        # Implementation depends on how referral codes are passed through the system
        Rails.application.config.session_store == :cookie_store ? 
          cookies[:referral_code] : session[:referral_code]
      end
      
      def find_referrer(referral_code)
        Decidim::VolunteerScheduler::VolunteerProfile
          .find_by(referral_code: referral_code)
          &.user
      end
      
      def cleanup_volunteer_data
        # This ensures referral chains are properly handled when a user is deleted
        if volunteer_profile
          # Deactivate referrals where this user was the referrer
          referrals_made.update_all(active: false)
          
          # Handle referrals where this user was referred
          # Optionally reassign to the next level up in the chain
          referrals_received.destroy_all
        end
      end
    end
  end
end

# Initialize the user extension
Rails.application.config.to_prepare do
  Decidim::User.include Decidim::VolunteerScheduler::UserExtensions
end