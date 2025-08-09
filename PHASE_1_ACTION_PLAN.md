# Phase 1 Action Plan - Ready for Implementation

## Current Status Assessment

### ✅ What's Already Working
1. **Database migrations** - All 9 migrations exist
2. **Basic models** - VolunteerProfile, TaskTemplate, TaskAssignment, Referral, ScicentTransaction
3. **Referral chain creation** - `Referral.create_referral_chain` method implemented
4. **XP system** - `add_xp` and level calculation in VolunteerProfile
5. **Component registration** - Properly registered with Decidim
6. **Basic controllers** - Dashboard and admin controllers exist
7. **Basic views/cells** - Dashboard, task card, XP progress cells

### 🔴 What's Missing/Broken for Phase 1 MVP

## Priority 1: Fix Organization-Level Architecture

The current implementation has a mismatch between organization-level and component-level resources. Based on the docs:
- **Task Templates** should be organization-level (created by org admins)
- **Volunteer Profiles** should be component-scoped (participation context)

### Action Items:

1. **Fix VolunteerProfile associations**
```ruby
# Current issue: VolunteerProfile belongs to component but needs organization
# Fix: Add organization association, make component optional for org-wide tracking
belongs_to :organization, class_name: "Decidim::Organization"
belongs_to :component, class_name: "Decidim::Component", optional: true
```

2. **Update referral chain logic**
```ruby
# Current issue: Referral chain uses component for commission rates
# Fix: Use organization-level settings with component override capability
```

## Priority 2: Complete Task Assignment Workflow

### Required Actions:

1. **Add TaskAssignmentsController#accept action**
```ruby
def accept
  @task_template = TaskTemplate.find(params[:task_template_id])
  
  # Check volunteer can accept (level, not already assigned, etc.)
  if can_accept_task?(@task_template)
    @assignment = TaskAssignment.create!(
      task_template: @task_template,
      assignee: current_volunteer_profile,
      status: :pending,
      assigned_at: Time.current,
      due_date: calculate_due_date(@task_template)
    )
    
    flash[:notice] = t(".success")
    redirect_to task_assignment_path(@assignment)
  else
    flash[:alert] = t(".error")
    redirect_to dashboard_path
  end
end
```

2. **Integrate with Decidim Follow-up System**
```ruby
# In TaskAssignment model
def create_follow_up
  # Use Decidim's follow-up system for task submission
  follow_up = Decidim::FollowUp.create!(
    followable: self,
    user: assignee.user,
    decidim_component_id: task_template.component&.id
  )
end
```

3. **Add submission interface**
- Create view: `/app/views/decidim/volunteer_scheduler/task_assignments/show.html.erb`
- Add submission form using follow-up
- Display task details and requirements

## Priority 3: User Registration with Referral Codes

### Required Implementation:

1. **Capture referral code from URL**
```ruby
# In ApplicationController or dedicated controller
before_action :store_referral_code

def store_referral_code
  if params[:ref].present?
    session[:referral_code] = params[:ref]
  end
end
```

2. **Process after user confirmation**
```ruby
# Hook into Devise confirmable callback
# In User model concern or after_confirmation callback
def process_referral_after_confirmation
  if session[:referral_code].present?
    referrer = VolunteerProfile.find_by(referral_code: session[:referral_code])
    if referrer && referrer != self.volunteer_profile
      Referral.create_referral_chain(referrer, self.volunteer_profile)
    end
  end
end
```

## Priority 4: Complete Admin Review Interface

### Required Views and Actions:

1. **Admin task review page**
```erb
<!-- /app/views/decidim/volunteer_scheduler/admin/task_assignments/index.html.erb -->
- Filter by status (pending review, approved, rejected)
- Display submission details from follow-up
- Approve/Reject buttons with comment field
- Bulk operations support
```

2. **Review actions in controller**
```ruby
def approve
  @assignment = TaskAssignment.find(params[:id])
  @assignment.approve!(current_user, params[:review_notes])
  
  # Award XP
  @assignment.assignee.add_xp(@assignment.task_template.xp_reward)
  
  # Trigger commission calculation
  ReferralCommissionJob.perform_later(@assignment.assignee.id, @assignment.task_template.xp_reward)
  
  flash[:notice] = t(".success")
  redirect_to admin_task_assignments_path
end
```

## Priority 5: Implement Notifications

### Event Classes to Create:

1. **Create event files**
```ruby
# /app/events/decidim/volunteer_scheduler/task_approved_event.rb
module Decidim::VolunteerScheduler
  class TaskApprovedEvent < Decidim::Events::SimpleEvent
    def resource_title
      resource.task_template.title
    end
    
    def resource_path
      task_assignment_path(resource)
    end
  end
end
```

2. **Register events in engine.rb**
```ruby
initializer "decidim.volunteer_scheduler.events" do
  Decidim::EventsManager.subscribe("decidim.volunteer_scheduler.task_approved") do |event_name, data|
    TaskApprovedEvent.publish(
      resource: data[:task_assignment],
      affected_users: [data[:task_assignment].assignee.user]
    )
  end
end
```

## Priority 6: Create Missing Views

### Dashboard View Enhancement
```erb
<!-- /app/views/decidim/volunteer_scheduler/dashboard/index.html.erb -->
<div class="volunteer-dashboard">
  <!-- XP Progress Section -->
  <%= cell("decidim/volunteer_scheduler/xp_progress", current_volunteer_profile) %>
  
  <!-- Available Tasks -->
  <div class="available-tasks">
    <h2><%= t(".available_tasks") %></h2>
    <% @available_tasks.each do |task| %>
      <%= cell("decidim/volunteer_scheduler/task_card", task) %>
    <% end %>
  </div>
  
  <!-- Referral Section -->
  <div class="referral-section">
    <h3><%= t(".your_referral_code") %></h3>
    <input type="text" value="<%= referral_url(current_volunteer_profile) %>" readonly>
    <button class="copy-referral">Copy Link</button>
    
    <div class="referral-stats">
      <p>Total Referrals: <%= @referral_stats[:total_referrals] %></p>
      <p>Active Referrals: <%= @referral_stats[:active_referrals] %></p>
    </div>
  </div>
  
  <!-- My Assignments -->
  <div class="my-assignments">
    <h3><%= t(".my_assignments") %></h3>
    <% @my_assignments.each do |assignment| %>
      <%= render partial: "assignment_row", locals: { assignment: assignment } %>
    <% end %>
  </div>
</div>
```

## Testing Checklist

### Manual Testing Flow:
1. [ ] Create organization-level task templates as admin
2. [ ] Sign up new user with referral code in URL
3. [ ] Verify volunteer profile created on first component access
4. [ ] Accept a task from dashboard
5. [ ] Submit task completion via follow-up
6. [ ] Admin reviews and approves task
7. [ ] Verify XP awarded and level updated
8. [ ] Check notifications received
9. [ ] Verify referral chain created (check database)
10. [ ] Test commission calculation triggered

### Rails Console Testing:
```ruby
# Test referral chain creation
user1 = Decidim::User.first
user2 = Decidim::User.second
profile1 = user1.volunteer_profile || VolunteerProfile.create!(user: user1, organization: user1.organization)
profile2 = user2.volunteer_profile || VolunteerProfile.create!(user: user2, organization: user2.organization)

Decidim::VolunteerScheduler::Referral.create_referral_chain(profile1, profile2)

# Check chain created
Decidim::VolunteerScheduler::Referral.where(referred: profile2).count # Should be 1-5 depending on chain depth

# Test XP and level up
profile1.add_xp(50)
puts "Level: #{profile1.level}, XP: #{profile1.total_xp}"

# Test task assignment
template = Decidim::VolunteerScheduler::TaskTemplate.first
assignment = Decidim::VolunteerScheduler::TaskAssignment.create!(
  task_template: template,
  assignee: profile1,
  status: :pending
)
assignment.approve!(Decidim::User.find_by(admin: true), "Good work!")
```

## File Structure Verification

```bash
# Verify all required files exist
ls -la app/controllers/decidim/volunteer_scheduler/
ls -la app/views/decidim/volunteer_scheduler/dashboard/
ls -la app/models/decidim/volunteer_scheduler/
ls -la app/cells/decidim/volunteer_scheduler/
ls -la app/events/decidim/volunteer_scheduler/  # May need to create
ls -la app/jobs/decidim/volunteer_scheduler/
```

## Next Immediate Steps

1. **Test database state**:
   ```bash
   rails console
   # Check if tables exist
   ActiveRecord::Base.connection.tables.grep(/volunteer_scheduler/)
   ```

2. **Fix model associations** (Priority 1)

3. **Create missing controllers/actions** (Priority 2)

4. **Add follow-up integration** (Priority 2)

5. **Create notification events** (Priority 5)

6. **Enhance views** (Priority 6)

7. **Test complete workflow** (Testing Checklist)

## Success Criteria

Phase 1 is complete when:
- ✅ Volunteers can sign up with referral codes
- ✅ 5-level referral chains are created automatically
- ✅ Volunteers can accept tasks at their level
- ✅ Volunteers can submit tasks via follow-up
- ✅ Admins can review and approve/reject tasks
- ✅ XP is awarded and levels update automatically
- ✅ Notifications work for all major events
- ✅ Dashboard shows all volunteer information
- ✅ Referral code sharing works
- ✅ Complete workflow can be demonstrated end-to-end

---

**Estimated Time**: 3-5 days with focused implementation
**Next Action**: Start with Priority 1 - Fix organization/component architecture