# frozen_string_literal: true

namespace :decidim do
  namespace :volunteer_scheduler do
    desc "Install migrations from decidim-volunteer_scheduler to application"
    task install: %i(install:migrations seed_data)

    namespace :install do
      desc "Copy decidim-volunteer_scheduler migrations to application"
      task :migrations do
        ENV["FROM"] = "decidim_volunteer_scheduler"
        Rake::Task["railties:install:migrations"].invoke
      end
    end

    desc "Create seed data for volunteer scheduler"
    task seed_data: :environment do
      Decidim::VolunteerScheduler::Seeds.seed!
    end

    desc "Create sample volunteer profiles for existing users"
    task create_volunteer_profiles: :environment do
      puts "Creating volunteer profiles for existing confirmed users..."
      
      created_count = 0
      Decidim::User.joins(:organization).where.not(confirmed_at: nil).where(deleted_at: nil, managed: false).find_each do |user|
        unless user.volunteer_profile.present?
          begin
            profile = Decidim::VolunteerScheduler::VolunteerProfile.create!(
              user: user,
              organization: user.organization,
              level: 1,
              total_xp: 0,
              referral_code: generate_referral_code(user.organization),
              activity_multiplier: 1.0
            )
            created_count += 1
            puts "✓ Created profile for: #{user.email}"
          rescue => e
            puts "✗ Failed to create profile for #{user.email}: #{e.message}"
          end
        end
      end
      
      puts "Created #{created_count} volunteer profiles"
    end

    desc "Generate sample task assignments for testing"
    task generate_sample_assignments: :environment do
      puts "Creating sample task assignments..."
      
      Decidim::Organization.find_each do |org|
        templates = Decidim::VolunteerScheduler::TaskTemplate.where(organization: org).published.limit(3)
        volunteers = Decidim::VolunteerScheduler::VolunteerProfile.joins(:user).where(organization: org).limit(5)
        
        volunteers.each do |volunteer|
          templates.each do |template|
            next if volunteer.level < template.level_required
            
            assignment = Decidim::VolunteerScheduler::TaskAssignment.create!(
              task_template: template,
              assignee: volunteer,
              decidim_component: nil,  # Organization-level
              status: ['pending', 'submitted'].sample,
              assigned_at: rand(7.days).seconds.ago,
              due_date: rand(1..14).days.from_now
            )
            
            puts "✓ Assignment: #{volunteer.user.name} → #{template.title}"
          end
        end
      end
    end

    private

    def self.generate_referral_code(organization)
      loop do
        code = SecureRandom.alphanumeric(8).upcase
        break code unless Decidim::VolunteerScheduler::VolunteerProfile.exists?(
          referral_code: code,
          organization: organization
        )
      end
    end
  end
end