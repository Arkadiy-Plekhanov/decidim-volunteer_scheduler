# Decidim Volunteer Scheduler - Implementation Checklist

## Phase 1: Basic Module Setup ✅ (Ready to implement)

### 1.1 Generate Base Structure
```bash
cd /home/scicent/projects/decidim/development_app
rails generate decidim:component volunteer_scheduler
```

### 1.2 Database Setup
- [ ] Copy migration files from artifacts above
- [ ] Run migrations: `rails db:migrate`
- [ ] Verify tables are created correctly

### 1.3 Model Implementation
- [ ] Copy VolunteerProfile model
- [ ] Copy Referral model  
- [ ] Copy TaskTemplate model
- [ ] Copy TaskAssignment model
- [ ] Copy ScicentTransaction model
- [ ] Add User extensions

### 1.4 Component Registration
- [ ] Implement component.rb registration
- [ ] Add user extensions to User model
- [ ] Verify component appears in admin

## Phase 2: Core Functionality Testing 🔄 (Next priority)

### 2.1 Referral System Testing
- [ ] Test referral code generation
- [ ] Test 5-level referral chain creation
- [ ] Test commission distribution
- [ ] Verify activity multiplier calculations

### 2.2 Task System Testing  
- [ ] Create task templates via admin
- [ ] Test task assignment workflow
- [ ] Test XP and level progression
- [ ] Test Scicent token rewards

### 2.3 Integration Points
- [ ] Verify Decidim user integration
- [ ] Test component settings
- [ ] Test data export functionality
- [ ] Test event system integration

## Phase 3: Controllers and Views 📋 (After core models work)

### 3.1 Public Controllers
- [ ] DashboardController (volunteer dashboard)
- [ ] TemplatesController (available tasks)
- [ ] AssignmentsController (my assignments)
- [ ] ReferralsController (referral management)

### 3.2 Admin Controllers
- [ ] Admin::TemplatesController
- [ ] Admin::AssignmentsController  
- [ ] Admin::VolunteerProfilesController
- [ ] Admin::ReportsController

### 3.3 Views and UI
- [ ] Volunteer dashboard interface
- [ ] Task cards and assignment views
- [ ] Referral link interface
- [ ] Progress tracking components

## Phase 4: Advanced Features 🚀 (Final phase)

### 4.1 Background Jobs
- [ ] Implement referral commission job
- [ ] Activity multiplier recalculation
- [ ] Daily reminder system
- [ ] Level up notifications

### 4.2 Event System
- [ ] Task completion events
- [ ] Level up events  
- [ ] Referral reward events
- [ ] Commission earned events

### 4.3 Team Management (Optional)
- [ ] Team creation functionality
- [ ] Team membership management
- [ ] Team leadership features
- [ ] Mentoring system

## Critical Decision Points 🎯

### Decidim Invitation System Integration
**Question**: Does Decidim already have invitation features we should leverage?

**Research needed**:
- Check if `decidim-admin` has invitation functionality
- Look for existing referral/invitation patterns in Decidim codebase
- Determine if we should extend existing patterns or create new ones

### User Registration Integration  
**Implementation decision**: How to capture referral codes during registration?

**Options**:
1. Extend Decidim's registration form
2. Use URL parameters and sessions
3. Create custom registration flow

### Scicent Token Integration
**Question**: How will Scicent tokens integrate with external sales system?

**Considerations**:
- API endpoints for external system integration
- Webhook handling for sale notifications
- Commission calculation triggers

## Testing Strategy 🧪

### Unit Tests
- [ ] Model validations and business logic
- [ ] Referral chain creation
- [ ] Commission calculations
- [ ] Activity multiplier logic

### Integration Tests  
- [ ] Task assignment workflow
- [ ] User registration with referrals
- [ ] Admin task management
- [ ] Component lifecycle

### System Tests
- [ ] End-to-end volunteer journey
- [ ] Referral link sharing and signup
- [ ] Multi-level commission distribution
- [ ] Admin management workflows

## Production Considerations 🏭

### Performance
- [ ] Database indexing strategy
- [ ] Background job queue configuration
- [ ] Caching strategy for frequent queries
- [ ] Activity multiplier calculation optimization

### Security
- [ ] Referral code generation security
- [ ] Commission calculation validation
- [ ] Admin permission checks
- [ ] Data privacy compliance

### Monitoring
- [ ] Commission distribution tracking
- [ ] User engagement metrics
- [ ] Task completion rates
- [ ] Referral system performance

## Immediate Next Actions 📋

1. **Start with Phase 1.1** - Generate the base component structure
2. **Implement migrations** - Copy and run the database migrations
3. **Add core models** - Start with VolunteerProfile, then Referral
4. **Test referral system** - Verify 5-level chain creation works
5. **Create basic controllers** - Start with DashboardController
6. **Build minimal UI** - Simple dashboard to see it working

## Integration Questions to Research 🔍

1. **Decidim Invitations**: Check `decidim-admin` for existing invitation patterns
2. **User Registration**: How to extend registration with referral codes
3. **Component Settings**: Verify all settings work as expected
4. **Event System**: Test Decidim event integration works properly
5. **Data Export**: Ensure export functionality follows Decidim patterns

## Success Metrics 📊

**Phase 1 Success**: 
- Module loads without errors
- Database migrations complete
- Basic models work
- Component appears in admin

**Phase 2 Success**:
- Users can accept tasks
- XP and level system works
- Referral chains create correctly
- Basic commission distribution works

**Phase 3 Success**:
- Complete volunteer dashboard
- Admin can manage tasks
- Public-facing volunteer interface
- Referral sharing functionality

**Phase 4 Success**:
- Production-ready module
- Full test coverage
- Background job processing
- Performance optimized