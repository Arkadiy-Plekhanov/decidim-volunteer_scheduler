# frozen_string_literal: true

require "spec_helper"

describe "Volunteer Workflow", type: :system do
  include_context "with a component"
  let(:manifest_name) { "volunteer_scheduler" }
  let(:organization) { create(:organization) }
  let!(:user) { create(:user, :confirmed, organization: organization) }
  let!(:volunteer_profile) { create(:volunteer_profile, user: user, organization: organization, level: 1, total_xp: 50) }
  let!(:task_template) { create(:task_template, :level_1, component: component, organization: organization) }
  
  before do
    switch_to_host(organization.host)
    login_as user, scope: :user
  end
  
  describe "volunteer dashboard" do
    before do
      visit main_component_path(component)
    end
    
    it "displays volunteer profile information" do
      expect(page).to have_content("Level 1")
      expect(page).to have_content("50 XP")
      expect(page).to have_content(volunteer_profile.referral_code)
    end
    
    it "shows available tasks" do
      expect(page).to have_content(translated(task_template.title))
      expect(page).to have_content("#{task_template.xp_reward} XP")
      expect(page).to have_content("Level #{task_template.level_required} required")
    end
    
    it "allows accepting a task" do
      within ".task-card" do
        click_button "Accept Task"
      end
      
      expect(page).to have_content("Task accepted successfully")
      expect(volunteer_profile.task_assignments.count).to eq(1)
    end
  end
  
  describe "task submission" do
    let!(:task_assignment) { create(:task_assignment, assignee: volunteer_profile, task_template: task_template, status: :pending) }
    
    before do
      visit main_component_path(component)
    end
    
    it "allows submitting completed work" do
      within ".my-assignments" do
        click_link "Submit Work"
      end
      
      fill_in "Report", with: "I have completed this task successfully"
      fill_in "Hours worked", with: "2.5"
      fill_in "Challenges faced", with: "None"
      
      click_button "Submit"
      
      expect(page).to have_content("Task submitted successfully")
      expect(task_assignment.reload.status).to eq("submitted")
    end
    
    it "validates submission form" do
      within ".my-assignments" do
        click_link "Submit Work"
      end
      
      click_button "Submit"
      
      expect(page).to have_content("Report can't be blank")
      expect(page).to have_content("Hours worked can't be blank")
    end
  end
  
  describe "level progression" do
    let!(:task_assignment) { create(:task_assignment, :approved, assignee: volunteer_profile, task_template: task_template) }
    
    before do
      volunteer_profile.add_xp(50) # Total: 100 XP
      visit main_component_path(component)
    end
    
    it "shows level up notification" do
      expect(page).to have_content("Congratulations! You've reached Level 2")
      expect(page).to have_content("Level 2")
      expect(page).to have_content("100 XP")
    end
    
    it "unlocks level 2 tasks" do
      level_2_template = create(:task_template, :level_2, component: component, organization: organization)
      
      visit main_component_path(component)
      
      expect(page).to have_content(translated(level_2_template.title))
      expect(page).to have_button("Accept Task", count: 2)
    end
  end
  
  describe "referral system" do
    before do
      visit main_component_path(component)
    end
    
    it "displays referral code and link" do
      expect(page).to have_content("Your Referral Code")
      expect(page).to have_content(volunteer_profile.referral_code)
      expect(page).to have_content("Share this link")
    end
    
    it "tracks referral signups" do
      referral_link = decidim_volunteer_scheduler.root_path(ref: volunteer_profile.referral_code)
      
      logout
      
      visit referral_link
      
      click_link "Sign up"
      
      within ".new_user" do
        fill_in "Name", with: "New Volunteer"
        fill_in "Email", with: "newvolunteer@example.org"
        fill_in "Password", with: "Password123!"
        fill_in "Password confirmation", with: "Password123!"
        check "I agree to the Terms of Service"
        
        click_button "Sign up"
      end
      
      new_user = Decidim::User.last
      expect(new_user.volunteer_profile).to be_present
      
      referral = Decidim::VolunteerScheduler::Referral.find_by(
        referrer: volunteer_profile,
        referred: new_user
      )
      
      expect(referral).to be_present
      expect(referral.level).to eq(1)
      expect(referral.commission_rate).to eq(0.10)
    end
  end
  
  describe "activity multiplier" do
    before do
      # Complete multiple tasks to increase multiplier
      3.times do
        assignment = create(:task_assignment, assignee: volunteer_profile, task_template: task_template)
        assignment.update!(status: :approved, reviewed_at: Time.current)
      end
      
      volunteer_profile.calculate_activity_multiplier!
      visit main_component_path(component)
    end
    
    it "displays current multiplier" do
      expect(page).to have_content("Activity Multiplier")
      expect(page).to have_content("#{volunteer_profile.activity_multiplier}x")
    end
    
    it "applies multiplier to XP rewards" do
      new_template = create(:task_template, xp_reward: 100, component: component, organization: organization)
      expected_xp = (100 * volunteer_profile.activity_multiplier).round
      
      expect(page).to have_content("#{expected_xp} XP (with multiplier)")
    end
  end
end