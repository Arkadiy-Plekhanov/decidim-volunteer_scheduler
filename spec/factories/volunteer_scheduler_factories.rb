# frozen_string_literal: true

require "decidim/faker/localized"
require "decidim/core/test/factories"

FactoryBot.define do
  factory :volunteer_scheduler_component, parent: :component do
    name { generate(:component_name) }
    manifest_name { :volunteer_scheduler }
    participatory_space { create(:participatory_process, :with_steps, organization: organization) }
    
    trait :with_settings do
      settings do
        {
          xp_per_task: 50,
          max_daily_tasks: 3,
          referral_commission_l1: 0.10,
          referral_commission_l2: 0.08,
          referral_commission_l3: 0.06,
          referral_commission_l4: 0.04,
          referral_commission_l5: 0.02,
          level_thresholds: "100,500,1500",
          task_deadline_days: 7
        }
      end
    end
  end

  factory :volunteer_profile, class: "Decidim::VolunteerScheduler::VolunteerProfile" do
    user { create(:user, :confirmed) }
    organization { user.organization }
    level { 1 }
    total_xp { 0 }
    referral_code { SecureRandom.alphanumeric(8).upcase }
    activity_multiplier { 1.0 }
    
    trait :level_2 do
      level { 2 }
      total_xp { 150 }
      activity_multiplier { 1.1 }
    end
    
    trait :level_3 do
      level { 3 }
      total_xp { 600 }
      activity_multiplier { 1.2 }
    end
    
    trait :with_referrer do
      after(:create) do |profile|
        referrer = create(:volunteer_profile, organization: profile.organization)
        create(:referral, 
               referrer: referrer, 
               referred: profile.user,
               organization: profile.organization,
               level: 1,
               commission_rate: 0.10)
      end
    end
    
    trait :with_referral_chain do
      after(:create) do |profile|
        # Create a 3-level referral chain
        level_1_referrer = create(:volunteer_profile, organization: profile.organization)
        level_2_referrer = create(:volunteer_profile, organization: profile.organization)
        level_3_referrer = create(:volunteer_profile, organization: profile.organization)
        
        create(:referral, referrer: level_1_referrer, referred: profile.user, level: 1, commission_rate: 0.10, organization: profile.organization)
        create(:referral, referrer: level_2_referrer, referred: profile.user, level: 2, commission_rate: 0.08, organization: profile.organization)
        create(:referral, referrer: level_3_referrer, referred: profile.user, level: 3, commission_rate: 0.06, organization: profile.organization)
      end
    end
  end

  factory :task_template, class: "Decidim::VolunteerScheduler::TaskTemplate" do
    organization
    component { create(:volunteer_scheduler_component, organization: organization) }
    title { generate(:localized_title) }
    description { Decidim::Faker::Localized.wrapped("<p>", "</p>") { generate(:localized_sentence, word_count: 20) } }
    xp_reward { [20, 50, 100].sample }
    scicent_reward { [0, 5, 10, 20].sample }
    level_required { 1 }
    category { %w[outreach technical administrative].sample }
    frequency { %w[daily weekly monthly one_time].sample }
    status { :published }
    deadline_days { 7 }
    max_assignments_per_day { 10 }
    
    trait :level_1 do
      level_required { 1 }
      xp_reward { 20 }
    end
    
    trait :level_2 do
      level_required { 2 }
      xp_reward { 50 }
    end
    
    trait :level_3 do
      level_required { 3 }
      xp_reward { 100 }
    end
    
    trait :draft do
      status { :draft }
    end
    
    trait :archived do
      status { :archived }
    end
    
    trait :with_instructions do
      instructions { "Step 1: Do this\nStep 2: Do that\nStep 3: Submit your work" }
      metadata do
        {
          skills_required: ["communication", "organization"],
          estimated_hours: 2
        }
      end
    end
  end

  factory :task_assignment, class: "Decidim::VolunteerScheduler::TaskAssignment" do
    task_template
    assignee { create(:volunteer_profile, organization: task_template.organization) }
    component { task_template.component }
    status { :pending }
    assigned_at { Time.current }
    due_date { 7.days.from_now }
    
    trait :submitted do
      status { :submitted }
      submitted_at { 1.day.ago }
      submission_notes { "I have completed this task successfully" }
      submission_data do
        {
          hours_worked: 2.5,
          challenges_faced: "None",
          attachments: []
        }
      end
    end
    
    trait :approved do
      status { :approved }
      submitted_at { 2.days.ago }
      reviewed_at { 1.day.ago }
      reviewer { create(:user, :admin, organization: task_template.organization) }
      admin_notes { "Great work!" }
      submission_data do
        {
          hours_worked: 2.5,
          challenges_faced: "None",
          attachments: []
        }
      end
    end
    
    trait :rejected do
      status { :rejected }
      submitted_at { 2.days.ago }
      reviewed_at { 1.day.ago }
      reviewer { create(:user, :admin, organization: task_template.organization) }
      admin_notes { "Please resubmit with more details" }
    end
    
    trait :overdue do
      due_date { 1.day.ago }
    end
  end

  factory :referral, class: "Decidim::VolunteerScheduler::Referral" do
    organization
    referrer { create(:volunteer_profile, organization: organization) }
    referred { create(:user, :confirmed, organization: organization) }
    level { 1 }
    commission_rate { 0.10 }
    status { :active }
    
    trait :level_2 do
      level { 2 }
      commission_rate { 0.08 }
    end
    
    trait :level_3 do
      level { 3 }
      commission_rate { 0.06 }
    end
    
    trait :inactive do
      status { :inactive }
    end
  end

  factory :scicent_transaction, class: "Decidim::VolunteerScheduler::ScicentTransaction" do
    user { create(:user, :confirmed) }
    transaction_type { :task_reward }
    amount { 50 }
    status { :completed }
    
    trait :referral_commission do
      transaction_type { :referral_commission }
      amount { 10 }
      metadata do
        {
          referral_level: 1,
          referred_user_id: create(:user).id,
          commission_rate: 0.10
        }
      end
    end
    
    trait :pending do
      status { :pending }
    end
    
    trait :failed do
      status { :failed }
      metadata { { error: "Insufficient balance" } }
    end
  end
end