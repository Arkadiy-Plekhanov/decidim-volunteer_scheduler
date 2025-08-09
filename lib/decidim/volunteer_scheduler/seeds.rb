# frozen_string_literal: true

module Decidim
  module VolunteerScheduler
    # Seeds for the volunteer scheduler module
    class Seeds
      def self.seed!
        puts "🌱 Seeding Volunteer Scheduler..."
        
        # Create sample data for each organization
        Decidim::Organization.find_each do |organization|
          create_sample_task_templates(organization)
          create_sample_volunteer_users(organization)
        end
        
        puts "✓ Volunteer Scheduler seed data completed!"
      end

      private

      def self.create_sample_task_templates(organization)
        org_name = organization.name.is_a?(Hash) ? organization.name[I18n.locale.to_s] || organization.name.values.first : organization.name
        puts "  Creating task templates for #{org_name}..."
        
        task_templates = [
          {
            title: "Phone Banking - Contact Voters",
            description: "Contact registered voters to discuss upcoming election.",
            xp_reward: 50,
            level_required: 1,
            category: "outreach",
            frequency: "daily"
          },
          {
            title: "Door-to-Door Canvassing",
            description: "Visit houses in assigned neighborhood.",
            xp_reward: 100,
            level_required: 2,
            category: "outreach",
            frequency: "weekly"
          },
          {
            title: "Social Media Content Creation",
            description: "Create social media posts promoting campaign.",
            xp_reward: 75,
            level_required: 1,
            category: "technical",
            frequency: "weekly"
          },
          {
            title: "Event Setup and Coordination",
            description: "Help set up campaign events.",
            xp_reward: 125,
            level_required: 2,
            category: "administrative",
            frequency: "monthly"
          },
          {
            title: "Voter Registration Drive",
            description: "Register new voters at community events.",
            xp_reward: 150,
            level_required: 3,
            category: "outreach",
            frequency: "monthly"
          }
        ]

        task_templates.each do |template_data|
          # Check if template already exists by title
          existing_template = Decidim::VolunteerScheduler::TaskTemplate.find_by(
            title: template_data[:title],
            organization: organization
          )
          
          unless existing_template
            template = Decidim::VolunteerScheduler::TaskTemplate.create!(
              title: template_data[:title],
              description: template_data[:description],
              xp_reward: template_data[:xp_reward],
              level_required: template_data[:level_required],
              category: template_data[:category],
              frequency: template_data[:frequency],
              status: "published",
              organization: organization,
              component: nil  # Organization-level
            )
            
            puts "    ✓ #{template.title}"
          end
        end
      end

      def self.create_sample_volunteer_users(organization)
        org_name = organization.name.is_a?(Hash) ? organization.name[I18n.locale.to_s] || organization.name.values.first : organization.name
        puts "  Creating sample volunteer users for #{org_name}..."
        
        volunteers = [
          {
            email: "volunteer1@gmail.com",
            name: "Alice Volunteer",
            nickname: "alice_vol_#{organization.id}",
            password: "decidim_alice_password123!"
          },
          {
            email: "volunteer2@gmail.com",
            name: "Bob Volunteer",
            nickname: "bob_vol_#{organization.id}",
            password: "decidim_bob_password456!"
          },
          {
            email: "volunteer3@gmail.com",
            name: "Carol Volunteer",
            nickname: "carol_vol_#{organization.id}",
            password: "decidim_carol_password789!"
          }
        ]

        # Disable confirmation emails during seeding
        if defined?(Devise::Mailer)
          original_perform_deliveries = Devise::Mailer.perform_deliveries
          Devise::Mailer.perform_deliveries = false
        end

        volunteers.each do |volunteer_data|
          existing_user = Decidim::User.find_by(
            email: volunteer_data[:email],
            organization: organization
          )
          
          unless existing_user
            user = Decidim::User.new(
              email: volunteer_data[:email],
              name: volunteer_data[:name],
              nickname: volunteer_data[:nickname],
              password: volunteer_data[:password],
              password_confirmation: volunteer_data[:password],
              organization: organization,
              accepted_tos_version: organization.tos_version,
              locale: organization.default_locale || I18n.locale,
              tos_agreement: true  # Accept terms of service
            )
            
            # Skip email confirmation
            user.skip_confirmation!
            user.save!
            
            puts "    ✓ User: #{user.email} (password: #{volunteer_data[:password]})"
          end
        end

        # Re-enable confirmation emails
        if defined?(Devise::Mailer)
          Devise::Mailer.perform_deliveries = original_perform_deliveries
        end
      end
    end
  end
end