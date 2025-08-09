# frozen_string_literal: true

# Seeds for development and staging environments
# Run with: rails decidim_volunteer_scheduler:seed

require "decidim/faker/localized"

module Decidim
  module VolunteerScheduler
    class Seeds
      def self.call(organization, participatory_space = nil)
        new(organization, participatory_space).call
      end
      
      def initialize(organization, participatory_space = nil)
        @organization = organization
        @participatory_space = participatory_space || create_test_process
      end
      
      def call
        puts "🌱 Seeding Volunteer Scheduler for #{organization.name['en']}..."
        
        create_component
        create_task_templates
        create_volunteer_profiles
        create_task_assignments
        create_referral_chains
        
        puts "✅ Volunteer Scheduler seeding complete!"
      end
      
      private
      
      attr_reader :organization, :participatory_space
      
      def create_test_process
        Decidim::ParticipatoryProcess.create!(
          title: Decidim::Faker::Localized.sentence(word_count: 3),
          slug: "volunteer-test-#{SecureRandom.hex(4)}",
          subtitle: Decidim::Faker::Localized.sentence(word_count: 5),
          description: Decidim::Faker::Localized.wrapped("<p>", "</p>") do
            Decidim::Faker::Localized.paragraph(sentence_count: 3)
          end,
          short_description: Decidim::Faker::Localized.sentence(word_count: 10),
          organization: organization,
          hero_image: File.open(Rails.root.join("public/hero.jpg")),
          banner_image: File.open(Rails.root.join("public/banner.jpg")),
          published_at: Time.current,
          start_date: 1.month.ago,
          end_date: 6.months.from_now
        )
      rescue Errno::ENOENT
        # If images don't exist, create without them
        Decidim::ParticipatoryProcess.create!(
          title: Decidim::Faker::Localized.sentence(word_count: 3),
          slug: "volunteer-test-#{SecureRandom.hex(4)}",
          subtitle: Decidim::Faker::Localized.sentence(word_count: 5),
          description: Decidim::Faker::Localized.wrapped("<p>", "</p>") do
            Decidim::Faker::Localized.paragraph(sentence_count: 3)
          end,
          short_description: Decidim::Faker::Localized.sentence(word_count: 10),
          organization: organization,
          published_at: Time.current,
          start_date: 1.month.ago,
          end_date: 6.months.from_now
        )
      end
      
      def create_component
        @component = Decidim::Component.find_or_create_by!(
          manifest_name: "volunteer_scheduler",
          participatory_space: participatory_space
        ) do |c|
          c.name = { "en" => "Volunteer Tasks", "es" => "Tareas Voluntarias", "ca" => "Tasques Voluntàries" }
          c.published_at = Time.current
          c.settings = {
            xp_per_task: 50,
            max_daily_tasks: 5,
            referral_commission_l1: 0.10,
            referral_commission_l2: 0.08,
            referral_commission_l3: 0.06,
            referral_commission_l4: 0.04,
            referral_commission_l5: 0.02,
            level_thresholds: "100,500,1500",
            task_deadline_days: 7
          }
        end
        
        puts "  ✓ Component created: #{@component.name['en']}"
      end
      
      def create_task_templates
        puts "  Creating task templates..."
        
        # Level 1 tasks
        5.times do |i|
          create_task_template(
            title: "Beginner Task #{i + 1}",
            description: "A simple task suitable for new volunteers",
            level_required: 1,
            xp_reward: [20, 30, 40].sample,
            category: %w[outreach administrative].sample
          )
        end
        
        # Level 2 tasks
        3.times do |i|
          create_task_template(
            title: "Intermediate Task #{i + 1}",
            description: "A moderately complex task requiring some experience",
            level_required: 2,
            xp_reward: [50, 60, 70].sample,
            category: %w[technical content_creation].sample
          )
        end
        
        # Level 3 tasks
        2.times do |i|
          create_task_template(
            title: "Advanced Task #{i + 1}",
            description: "A challenging task for experienced volunteers",
            level_required: 3,
            xp_reward: [80, 90, 100].sample,
            category: %w[training mentoring].sample
          )
        end
        
        puts "  ✓ Created #{TaskTemplate.count} task templates"
      end
      
      def create_task_template(attrs)
        TaskTemplate.create!(
          organization: organization,
          component: @component,
          title: Decidim::Faker::Localized.sentence(word_count: 3),
          description: Decidim::Faker::Localized.wrapped("<p>", "</p>") do
            Decidim::Faker::Localized.paragraph(sentence_count: 3)
          end,
          level_required: attrs[:level_required],
          xp_reward: attrs[:xp_reward],
          scicent_reward: attrs[:xp_reward] / 10.0,
          category: attrs[:category],
          frequency: %w[one_time daily weekly monthly].sample,
          status: :published,
          deadline_days: 7,
          max_assignments_per_day: 10,
          instructions: "1. Review the task requirements\n2. Complete the work\n3. Submit your results",
          metadata: {
            skills_required: %w[communication organization teamwork].sample(2),
            estimated_hours: [1, 2, 3, 4].sample
          }
        )
      end
      
      def create_volunteer_profiles
        puts "  Creating volunteer profiles..."
        
        # Create test users if needed
        10.times do |i|
          user = Decidim::User.find_or_create_by!(
            email: "volunteer#{i + 1}@example.org"
          ) do |u|
            u.name = "Volunteer #{i + 1}"
            u.nickname = "volunteer_#{i + 1}"
            u.password = "Password123!"
            u.password_confirmation = "Password123!"
            u.organization = organization
            u.confirmed_at = Time.current
            u.locale = organization.default_locale
            u.tos_agreement = true
            u.accepted_tos_version = organization.tos_version
          end
          
          profile = VolunteerProfile.find_or_create_by!(
            user: user,
            organization: organization
          ) do |p|
            p.level = [1, 1, 1, 2, 2, 3].sample
            p.total_xp = p.level == 1 ? rand(0..99) : p.level == 2 ? rand(100..499) : rand(500..1500)
            p.referral_code = SecureRandom.alphanumeric(8).upcase
            p.activity_multiplier = 1.0 + (p.level - 1) * 0.1
            p.metadata = {
              onboarded: true,
              preferred_categories: %w[outreach technical administrative].sample(2)
            }
          end
          
          @volunteer_profiles ||= []
          @volunteer_profiles << profile
        end
        
        puts "  ✓ Created #{VolunteerProfile.count} volunteer profiles"
      end
      
      def create_task_assignments
        puts "  Creating task assignments..."
        
        templates = TaskTemplate.published
        
        @volunteer_profiles.each do |profile|
          # Assign 1-3 tasks to each volunteer
          eligible_templates = templates.where("level_required <= ?", profile.level).sample(rand(1..3))
          
          eligible_templates.each do |template|
            assignment = TaskAssignment.create!(
              task_template: template,
              assignee: profile,
              component: @component,
              status: [:pending, :submitted, :approved].sample,
              assigned_at: rand(7.days.ago..Time.current),
              due_date: rand(1.day.from_now..7.days.from_now)
            )
            
            # Add submission data for submitted/approved tasks
            if assignment.submitted? || assignment.approved?
              assignment.update!(
                submitted_at: assignment.assigned_at + rand(1..5).days,
                submission_notes: "Task completed successfully",
                submission_data: {
                  hours_worked: rand(1.0..4.0).round(1),
                  challenges_faced: "None",
                  quality_rating: rand(3..5)
                }
              )
            end
            
            # Add review data for approved tasks
            if assignment.approved?
              admin = Decidim::User.where(admin: true, organization: organization).first
              assignment.update!(
                reviewed_at: assignment.submitted_at + rand(1..2).days,
                reviewer: admin,
                admin_notes: "Great work!"
              )
              
              # Award XP
              profile.add_xp(template.xp_reward)
            end
          end
        end
        
        puts "  ✓ Created #{TaskAssignment.count} task assignments"
      end
      
      def create_referral_chains
        puts "  Creating referral chains..."
        
        # Create referral relationships
        referrers = @volunteer_profiles.first(3)
        referred_profiles = @volunteer_profiles.last(7)
        
        referrers.each_with_index do |referrer, i|
          # Each referrer gets 2-3 referrals
          referred_profiles.sample(rand(2..3)).each do |referred_profile|
            # Create 5-level referral chain
            5.times do |level|
              commission_rate = case level
                              when 0 then 0.10
                              when 1 then 0.08
                              when 2 then 0.06
                              when 3 then 0.04
                              when 4 then 0.02
                              end
              
              Referral.find_or_create_by!(
                referrer: referrer,
                referred: referred_profile.user,
                level: level + 1,
                organization: organization
              ) do |r|
                r.commission_rate = commission_rate
                r.status = :active
                r.metadata = {
                  signup_source: "referral_link",
                  campaign: "seed_data"
                }
              end
              
              break if level >= i # Limit chain depth based on referrer index
            end
          end
        end
        
        puts "  ✓ Created #{Referral.count} referral relationships"
      end
    end
  end
end

# Run seeds if called directly
if Rails.env.development? || Rails.env.staging?
  organization = Decidim::Organization.first
  
  if organization
    Decidim::VolunteerScheduler::Seeds.call(organization)
  else
    puts "⚠️  No organization found. Please create one first with: rails decidim:seed"
  end
end