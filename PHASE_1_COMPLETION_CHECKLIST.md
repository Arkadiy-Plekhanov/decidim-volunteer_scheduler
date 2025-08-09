# Phase 1 Completion Checklist - decidim-volunteer_scheduler

## 🎯 Phase 1 Goal
Deliver the **minimum viable volunteer management system** with task assignments, XP/levels, and 5-level referral system.

## 📋 Implementation Status

### 1. Database & Models ⚠️ NEEDS FIXES

#### ✅ Migrations Created
- [x] 001_create_volunteer_profiles
- [x] 002_create_task_templates  
- [x] 003_create_task_assignments
- [x] 004_create_referrals
- [x] 005_create_scicent_transactions
- [x] 006-009_organization_level_adjustments

#### 🔧 Model Fixes Needed

**VolunteerProfile** - `/app/models/decidim/volunteer_scheduler/volunteer_profile.rb`
- [ ] Fix `calculate_level!` to use configurable thresholds
- [ ] Implement `generate_referral_code` method
- [ ] Add `create_volunteer_profile_if_needed` callback
- [ ] Test XP addition and level-up logic
- [ ] Add activity multiplier stub (default 1.0)

**Referral** - `/app/models/decidim/volunteer_scheduler/referral.rb`
- [ ] Implement `create_referral_chain` class method for 5-level creation
- [ ] Add loop prevention validation
- [ ] Set correct commission rates (10%, 8%, 6%, 4%, 2%)
- [ ] Add `active` flag and network size tracking

**TaskAssignment** - `/app/models/decidim/volunteer_scheduler/task_assignment.rb`
- [ ] Fix status workflow (pending → submitted → approved/rejected)
- [ ] Connect to follow-up system for submissions
- [ ] Implement `submit_work!` method
- [ ] Add XP award on approval
- [ ] Trigger referral commission job

**TaskTemplate** - `/app/models/decidim/volunteer_scheduler/task_template.rb`
- [ ] Add frequency enum (daily, weekly, monthly, one_time)
- [ ] Add level requirements validation
- [ ] Implement `available_for_level` scope
- [ ] Add category field for task organization

### 2. Controllers & Views 🔴 NEEDS IMPLEMENTATION

#### Public Controllers
**DashboardController** - `/app/controllers/decidim/volunteer_scheduler/dashboard_controller.rb`
- [ ] Show volunteer profile with XP/level
- [ ] Display available tasks filtered by level
- [ ] Show referral code and link
- [ ] Display referral tree (5 levels)
- [ ] Show completed/pending assignments

**TaskAssignmentsController** - `/app/controllers/decidim/volunteer_scheduler/task_assignments_controller.rb`
- [ ] `accept` action - create assignment
- [ ] `show` - display assignment details
- [ ] `submit` - integrate with follow-up
- [ ] `index` - list user's assignments

#### Admin Controllers  
**Admin::TaskAssignmentsController** - `/app/controllers/decidim/volunteer_scheduler/admin/task_assignments_controller.rb`
- [ ] Review interface with filters
- [ ] Approve/reject actions
- [ ] Add review comments
- [ ] Bulk operations support

**Admin::TaskTemplatesController** - Already exists ✅
- [x] CRUD operations
- [ ] Add level requirement field
- [ ] Add frequency selection
- [ ] Add XP reward configuration

### 3. User Integration 🔴 NEEDS IMPLEMENTATION

#### User Model Extension
- [ ] Add concern to extend Decidim::User
- [ ] Create volunteer profile on first component access
- [ ] Add referral code parameter to registration

#### Referral Code Binding
- [ ] Capture referral code from URL params
- [ ] Store in session during registration
- [ ] Create referral chain after user confirmation
- [ ] Validate referral code exists

### 4. Follow-up Integration 🔴 CRITICAL

- [ ] Use Decidim's follow-up for task submissions
- [ ] Create follow-up form for task reports
- [ ] Link follow-ups to task assignments
- [ ] Admin review through follow-up interface

### 5. Notifications 🔴 NEEDS IMPLEMENTATION

#### Event Classes
- [ ] `TaskAssignedEvent`
- [ ] `TaskApprovedEvent`
- [ ] `TaskRejectedEvent`  
- [ ] `LevelUpEvent`
- [ ] `ReferralRewardEvent`

#### Notification Triggers
- [ ] On task assignment
- [ ] On task approval/rejection
- [ ] On level up with capabilities unlock
- [ ] On referral commission earned

### 6. Views & UI Components ⚠️ PARTIAL

#### Cells (View Components)
- [x] DashboardCell - Basic structure exists
- [x] TaskCardCell - Basic structure exists
- [x] XpProgressCell - Basic structure exists
- [ ] ReferralTreeCell - Needs implementation
- [ ] LevelBadgeCell - Needs implementation

#### Dashboard Views
- [ ] `/app/views/decidim/volunteer_scheduler/dashboard/index.html.erb`
  - [ ] XP progress bar
  - [ ] Level badge with capabilities
  - [ ] Available tasks grid
  - [ ] Referral section with copy link
  - [ ] Recent activity feed

#### Task Views
- [ ] Task assignment page with submission form
- [ ] Task history with status badges
- [ ] Task details modal/page

### 7. Background Jobs 🔴 NEEDS IMPLEMENTATION

- [ ] `ReferralCommissionJob` - Calculate and distribute commissions
- [ ] `ActivityMultiplierJob` - Recalculate multipliers (stub for Phase 1)
- [ ] `LevelUpNotificationJob` - Send level-up notifications

### 8. Component Settings ⚠️ PARTIAL

In `/lib/decidim/volunteer_scheduler/component.rb`:
- [x] Basic settings structure
- [ ] Add XP threshold configuration
- [ ] Add referral commission rates
- [ ] Add task rotation settings
- [ ] Add notification preferences

### 9. Testing 🔴 NEEDS IMPLEMENTATION

#### Model Specs
- [ ] VolunteerProfile spec with XP/level tests
- [ ] Referral spec with chain creation tests
- [ ] TaskAssignment workflow tests
- [ ] TaskTemplate availability tests

#### System Tests
- [ ] Complete volunteer journey test
- [ ] Referral signup flow test
- [ ] Task acceptance and submission test
- [ ] Admin review workflow test

### 10. Seeds & Demo Data 🔴 NEEDS IMPLEMENTATION

- [ ] Create seed data for development
- [ ] Sample task templates (3 levels)
- [ ] Demo volunteer profiles
- [ ] Example referral chains
- [ ] Test assignments in various states

## 🚀 Implementation Order

### Step 1: Fix Core Models (Day 1-2)
1. Fix VolunteerProfile XP/level logic
2. Implement Referral.create_referral_chain
3. Fix TaskAssignment workflow
4. Test models in Rails console

### Step 2: User Integration (Day 2-3)
1. Extend User model with concern
2. Add referral code to registration
3. Create profile on component access
4. Test referral binding

### Step 3: Controllers & Basic Views (Day 3-4)
1. Implement DashboardController
2. Create dashboard view with XP/tasks
3. Implement task acceptance flow
4. Add admin review interface

### Step 4: Follow-up Integration (Day 4-5)
1. Connect to Decidim follow-up system
2. Create submission forms
3. Link to task assignments
4. Test submission workflow

### Step 5: Notifications & Jobs (Day 5-6)
1. Create event classes
2. Add notification triggers
3. Implement background jobs
4. Test notification delivery

### Step 6: Polish & Testing (Day 6-7)
1. Complete UI components
2. Add missing views
3. Write comprehensive tests
4. Create seed data

## ✅ Definition of Done for Phase 1

- [ ] Volunteer can see dashboard with XP/level
- [ ] Volunteer can accept tasks at their level
- [ ] Volunteer can submit task via follow-up
- [ ] Admin can review and approve/reject tasks
- [ ] XP awards and level-ups work correctly
- [ ] 5-level referral chains create properly
- [ ] Referral code sharing works
- [ ] Notifications trigger appropriately
- [ ] All tests pass
- [ ] Seed data demonstrates features

## 🔥 Critical Success Factors

1. **Follow-up Integration**: Must leverage Decidim's existing system
2. **Referral Chain**: 5-level creation without loops
3. **XP System**: Automatic level-ups with notifications
4. **Task Workflow**: Complete accept → submit → review cycle
5. **Component Integration**: Proper Decidim component behavior

## 📝 Notes

- Keep activity multiplier as stub (always 1.0) for Phase 1
- No token sale integration yet (Phase 2)
- No team features yet (Phase 2)
- Focus on core volunteer experience
- Use Decidim native features wherever possible

---

**Next Action**: Start with Step 1 - Fix Core Models, beginning with VolunteerProfile XP/level logic.