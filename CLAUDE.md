# CLAUDE.md - Decidim Volunteer Scheduler Module

## Project Overview

This is the **decidim-volunteer_scheduler** module - a comprehensive volunteer management system for the Decidim platform designed specifically for political organizations to engage volunteers through gamified tasks and token-based rewards. The module implements:

- **Task assignment and tracking system** with XP-based progression and 3-level capability unlocks
- **5-level referral system** with automatic commission distribution (10%, 8%, 6%, 4%, 2%)
- **Scicent token rewards** with external sales integration via webhooks
- **Activity multiplier system** with rolling 30-day windows and decay mechanisms
- **Team creation and mentoring capabilities** for volunteer leadership development
- **Daily/weekly/monthly budget allocation** with competitive bonus distributions
- **Real-time dashboard** with progress tracking and referral tree visualization

## Development Environment

**Platform**: Windows 11 with WSL2 Ubuntu  
**Path**: `\\wsl.localhost\Ubuntu\home\scicent\projects\decidim\development_app`  
**Decidim Version**: Latest development branch (0.30.1)  
**Target**: Single production-ready module for political volunteer engagement

### Decidim 0.30+ Specific Considerations

**⚠️ CRITICAL - Taxonomy System Revolution**: Decidim 0.30+ replaces the entire categorization system (Categories, Scopes, Areas, Process Types, Assembly Types) with a unified **Taxonomy System**. This affects how volunteer opportunities, skills, and scheduling categories are organized.

**Component Generation Pattern**:
```bash
# Generate external module (recommended for volunteer scheduler)  
decidim --component volunteer_scheduler --external --destination_folder ../decidim-module-volunteer-scheduler
```

**New Directory Structure** incorporates Webpacker changes:
```
decidim-module-volunteer-scheduler/
├── app/packs/                    # New Webpacker structure
│   ├── entrypoints/
│   └── src/
├── config/assets.rb              # Required for asset compilation
├── lib/decidim/volunteer_scheduler/
│   ├── component.rb              # Enhanced manifest with taxonomy support
│   └── engine.rb                 # Updated with asset path registration
└── spec/                         # Comprehensive test suite
```

## Development Commands

### Testing
```bash
# Run all tests
bundle exec rspec

# Run specific test files
bundle exec rspec spec/models/decidim/volunteer_scheduler/volunteer_profile_spec.rb
bundle exec rspec spec/system/decidim/volunteer_scheduler/volunteer_dashboard_spec.rb

# Run tests with coverage
COVERAGE=true bundle exec rspec
```

### Database Operations
```bash
# Run migrations
rails db:migrate

# Rollback migration
rails db:rollback

# Reset database (development only)
rails db:drop db:create db:migrate db:seed

# Create test database
RAILS_ENV=test rails db:create db:migrate
```

### Development Server
```bash
# Start development server
rails server

# Start with specific environment
RAILS_ENV=development rails server

# Start console
rails console

# Start console for testing
RAILS_ENV=test rails console
```

### Code Quality
```bash
# Run linter
bundle exec rubocop

# Auto-fix linting issues
bundle exec rubocop -a

# Run security audit
bundle exec brakeman

# Check for outdated gems
bundle outdated
```

### Asset Compilation
```bash
# Compile assets
rails assets:precompile

# Clean assets
rails assets:clean

# Run webpack dev server
./bin/webpack-dev-server
```

## Project Structure

```
decidim-volunteer_scheduler/
├── app/
│   ├── cells/                     # View components
│   ├── commands/                  # Business logic commands
│   ├── controllers/               # Public controllers
│   │   └── admin/                # Admin controllers
│   ├── events/                   # Decidim event integrations
│   ├── forms/                    # Form objects
│   ├── helpers/                  # View helpers
│   ├── jobs/                     # Background jobs
│   ├── models/                   # ActiveRecord models
│   ├── permissions/              # Authorization logic
│   ├── queries/                  # Query objects
│   ├── serializers/              # API serializers
│   ├── services/                 # Service objects
│   └── views/                    # View templates
├── config/
│   ├── locales/                  # Internationalization
│   └── routes.rb                 # Route definitions
├── db/migrate/                   # Database migrations
├── lib/                          # Library code
│   └── decidim/volunteer_scheduler/
├── spec/                         # Test files
└── app/packs/                    # Webpacker assets
```

## Core Models

### VolunteerProfile
- **Purpose**: Extended user profiles with XP, levels, and referral tracking  
- **Key Fields**: `level`, `total_xp`, `referral_code`, `activity_multiplier`
- **Relationships**: `belongs_to :user`, `has_many :task_assignments`
- **Decidim Pattern**: Uses `has_one :volunteer_profile, dependent: :destroy` association pattern
- **Extensions**: Implements concern modules rather than modifying core User model

### TaskTemplate  
- **Purpose**: Define reusable task templates with XP rewards
- **Key Fields**: `title`, `description`, `level`, `xp_reward`, `scicent_reward`
- **Categories**: Uses Decidim 0.30+ Taxonomy System instead of legacy categories  
- **Decidim Integration**: Inherits from `Decidim::HasComponent` for proper scoping
- **Table Name**: `decidim_volunteer_scheduler_task_templates`

### TaskAssignment
- **Purpose**: Track individual task assignments to volunteers
- **States**: pending → in_progress → submitted → completed/rejected
- **Key Fields**: `assignee_id`, `status`, `assigned_at`, `completed_at`
- **Event Integration**: Generates Decidim events for status changes and notifications
- **Follow-up Integration**: Leverages Decidim's follow-up system for task submissions

### Referral (Advanced Hierarchical Implementation)  
- **Purpose**: 5-level referral system with loop prevention and performance optimization
- **Commission Rates**: L1: 10%, L2: 8%, L3: 6%, L4: 4%, L5: 2%
- **Advanced Features**: 
  - PostgreSQL ltree extension for hierarchical queries
  - Ancestry gem with cache_depth for performance  
  - Referral loop prevention validation
  - Network size tracking and multiplier calculations
- **Security**: Anti-fraud detection with rate limiting and suspicious activity monitoring

### ScicentTransaction (Enhanced Wallet System)
- **Purpose**: Track Scicent token transactions and commissions
- **Types**: task_reward, referral_commission, sale_commission, admin_bonus
- **Fields**: `user_id`, `transaction_type`, `amount`, `status`

## Key Features

### XP and Level System
- **Level 1**: Basic tasks (0-99 XP)
- **Level 2**: Intermediate tasks + team creation (100-499 XP)  
- **Level 3**: Advanced tasks + leadership (500+ XP)
- **Capabilities**: Unlocked based on level progression

### Referral System
- Automatic 5-level chain creation on user signup
- Commission distribution on Scicent token sales
- Activity multiplier bonuses for active referrers
- Visual referral tree in dashboard

### Activity Multiplier
- Base: 1.0x for all users
- Level bonus: +0.1x per level above 1
- Activity bonus: +0.05x per 10 completed tasks (last month)
- Referral bonus: +0.1x per 5 active referrals
- Max multiplier: 3.0x

## Integration Points

### Decidim Native Features
- **Component Architecture**: Standard Decidim component registration
- **Event System**: Task completion, level-up notifications  
- **Follow-ups**: Used for task submissions and reports
- **Notifications**: In-app notifications for all major events
- **Admin Interface**: Full CRUD for templates and assignments
- **Permissions**: Role-based access control

### External Integrations
- **Scicent Token API**: Webhook integration for sales notifications
- **Commission Distribution**: Automated background job processing
- **Real-time Updates**: ActionCable for live dashboard updates

## Development Workflow

### Phase 1: Core Functionality
1. Basic models and migrations
2. Task assignment workflow
3. XP and level progression
4. Simple referral tracking
5. Admin interface for task management

### Phase 2: Advanced Features  
1. Activity multiplier calculations
2. Token sale webhook integration
3. Commission distribution system
4. Team creation and management
5. Performance optimizations

### Phase 3: Production Readiness
1. Comprehensive testing suite
2. Performance monitoring
3. Security hardening  
4. Backup and recovery procedures
5. Documentation and deployment guides

## Testing Strategy

### Test Coverage Areas
- **Models**: Business logic, validations, associations
- **Controllers**: Authorization, request/response handling
- **Commands**: Task assignment and completion flows
- **Jobs**: Background processing and commission calculations
- **System**: End-to-end volunteer workflows
- **Performance**: Large-scale referral chain processing

### Factory Definitions
All models have comprehensive FactoryBot factories with traits for:
- Different user levels and capabilities
- Various task states and completions  
- Referral chains and commission scenarios
- Transaction types and statuses

## Configuration

### Component Settings
- **Global Settings**: Referral system enable/disable, XP thresholds, multiplier limits
- **Step Settings**: Task creation controls, assignment deadlines, leaderboard visibility
- **Customizable Values**: All XP rewards, commission rates, and level thresholds

### Activity Multiplier Configuration (Best Practices)
Based on comprehensive analysis of gamification best practices:

```yaml
activity_multiplier:
  measurement_window: 30 # days (rolling window)
  decay_mechanism: 0.25 # 25% decay every 7 days of inactivity
  base_multiplier: 1.0
  max_multiplier: 3.0
  granularity: 0.01
  
  action_weights:
    task_completion: 1
    high_difficulty_tasks: 2
    token_sales: 0.1 # per $10 of sales
    referral_activity: 0.5 # bonus multiplier
  
  referral_influence: # diminishing returns per level
    level_1: 0.20 # 20% of referred volunteer's multiplier
    level_2: 0.10 # 10%
    level_3: 0.05 # 5%
    level_4: 0.02 # 2%
    level_5: 0.02 # 2%
```

### Budget Allocation Strategy
```yaml
budget_distribution:
  frequency: monthly # calendar month
  budget_type: variable_profit_percentage
  leftover_handling: roll_to_next_period
  
  weekly_structure:
    core_allocation: 85% # divided equally across 4 weeks
    bonus_pool: 15% # for top performers
    
  daily_breakdown:
    steady_floor: 90% # predictable daily share
    competitive_ceiling: 10% # bonus for top 5 daily performers
```

### Referral Commission Rates
```yaml
referral_commissions:
  level_1: 0.10 # 10% immediate commission
  level_2: 0.05 # 5%
  level_3: 0.03 # 3%
  level_4: 0.02 # 2%
  level_5: 0.01 # 1%
  
  trigger: auto_credit_on_sale
  reversal_capability: true # admin can reverse/adjust
  audit_trail: true
```

### Environment Variables
- `SCICENT_API_KEY`: For external token API integration
- `SCICENT_WEBHOOK_SECRET`: Webhook validation secret
- `VOLUNTEER_SCHEDULER_MAX_ASSIGNMENTS`: Concurrent task limit per user
- `ACTIVITY_MULTIPLIER_MAX`: Maximum allowed activity multiplier
- `COMMISSION_CALCULATION_DELAY`: Seconds to wait before processing commissions
- `MONTHLY_BUDGET_POOL`: Default monthly token allocation

## Security Considerations

### Data Protection
- Referral codes use cryptographically secure random generation
- Commission calculations include validation against business rules
- Personal referral information is protected from unauthorized access
- All sensitive actions include audit logging

### Authorization
- Task assignments validate user level and capabilities
- Admin actions require proper authorization levels
- API endpoints include rate limiting and authentication
- GDPR compliance for user data export/deletion

## Performance Optimizations

### Database
- Strategic indexing on frequently queried fields
- Efficient queries for referral chain calculations  
- Background job processing for commission distribution
- Caching of frequently accessed volunteer statistics

### Application
- Cell-based view components for reusable UI elements
- Asynchronous processing of commission calculations
- Batch updates for activity multiplier recalculations
- WebSocket connections for real-time updates

## Monitoring and Observability

### Metrics Tracking
- Task assignment and completion rates
- XP distribution and level progression
- Referral chain performance and commissions
- Activity multiplier calculations and effectiveness

### Error Handling
- Comprehensive logging for all business operations
- Error notification system for failed background jobs
- Graceful degradation for external API failures
- Audit trails for all commission distributions

## Deployment Considerations

### Production Requirements
- Ruby 3.3+
- PostgreSQL with proper indexing
- Redis for background job processing
- Sidekiq for job queue management

### Monitoring Setup
- Application performance monitoring (New Relic/DataDog)
- Error tracking (Sentry/Bugsnag) 
- Database performance monitoring
- Background job queue monitoring

## Phase-Based Implementation Strategy

### Phase 1: MVP Foundation (Current Priority)
**Goal**: Deliver working volunteer task system with basic referral tracking

**Core Features**:
- Volunteer profiles with XP and level progression
- Task templates and assignment workflow  
- Basic 5-level referral chain creation
- Admin interface for task management
- Simple dashboard with progress tracking

**Success Criteria**:
- Module loads without errors
- Database migrations complete successfully
- Volunteers can accept and complete tasks
- XP and level system functions correctly
- Referral chains create properly

### Phase 2: Advanced Systems
**Goal**: Add sophisticated multiplier calculations and token integration

**Advanced Features**:
- Activity multiplier with rolling windows and decay
- Scicent token webhook integration for sales
- Commission distribution automation
- Team creation and mentoring capabilities
- Real-time dashboard updates via ActionCable

**Success Criteria**:
- Commission calculations work accurately
- Activity multipliers update correctly
- Token sales trigger proper distributions
- Teams can be created and managed

### Phase 3: Production Optimization
**Goal**: Scale for production deployment with monitoring and security

**Production Features**:
- Comprehensive monitoring and metrics
- Performance optimizations and caching
- Security hardening and audit logging
- Backup and disaster recovery procedures
- Full test coverage and documentation

**Success Criteria**:
- Handle 1000+ concurrent volunteers
- Process commission calculations efficiently
- Meet security and compliance requirements
- Deploy successfully to production

## Common Tasks

### Phase 1 Development Tasks
```bash
# Generate the base component
cd /home/scicent/projects/decidim/development_app
rails generate decidim:component volunteer_scheduler

# Run migrations in order
rails db:migrate

# Test basic functionality
rails console
# > user = Decidim::User.first
# > profile = user.volunteer_profile
# > profile.add_xp(50)

# Start development server
rails server
```

### Creating New Task Templates
1. Access admin interface at `/admin/volunteer_scheduler/task_templates`
2. Set appropriate level requirement and XP reward
3. Configure frequency (daily/weekly/monthly/one-time)
4. Test with volunteer account at appropriate level

### Managing Referral Commissions  
1. Monitor commission distribution via admin reports
2. Verify commission calculations in ScicentTransaction records
3. Handle disputes through manual transaction adjustments
4. Review referral chain integrity periodically

### Testing Referral System
```ruby
# Test referral chain creation
referrer = Decidim::User.find_by(email: "referrer@example.com")
referred = Decidim::User.find_by(email: "referred@example.com")

# Create 5-level chain
Decidim::VolunteerScheduler::Referral.create_referral_chain(referrer, referred)

# Verify chain created correctly
chains = Decidim::VolunteerScheduler::Referral.where(referred: referred)
puts chains.map { |r| "Level #{r.level}: #{r.commission_rate * 100}%" }
```

### Performance Troubleshooting
1. Check database query performance for slow endpoints
2. Monitor background job queue for backlog issues  
3. Verify cache hit rates for frequently accessed data
4. Review activity multiplier calculations for accuracy

### Debugging Failed Assignments
```ruby
# Check failed task assignments
failed_assignments = Decidim::VolunteerScheduler::TaskAssignment
                      .where(status: :rejected)
                      .includes(:task_template, :assignee)

failed_assignments.each do |assignment|
  puts "User: #{assignment.assignee.name}"
  puts "Task: #{assignment.task_template.title}"  
  puts "Reason: #{assignment.admin_notes}"
  puts "---"
end
```

## Critical Implementation Priorities

### 🚨 MUST DO FIRST - Module Foundation
1. **Generate Component Structure**:
   ```bash
   cd /home/scicent/projects/decidim/development_app
   rails generate decidim:component volunteer_scheduler
   ```

2. **Implement Database Schema**: Copy migrations from technical specification documents

3. **Create Core Models**: Start with `VolunteerProfile`, then `Referral`, then `TaskTemplate`

4. **Test Each Component**: Verify each model works before moving to next

5. **Add Component Registration**: Ensure module appears in Decidim admin

### ⚡ Phase 1 Implementation Order
**Week 1**: Database & Models
- [ ] Run component generator
- [ ] Add all 5 migration files
- [ ] Implement VolunteerProfile model with XP system  
- [ ] Test level progression in Rails console

**Week 2**: Task System
- [ ] Add TaskTemplate model
- [ ] Add TaskAssignment model  
- [ ] Create basic admin interface for tasks
- [ ] Test task acceptance workflow

**Week 3**: Referral Foundation
- [ ] Add Referral model with 5-level chain logic
- [ ] Test referral creation and commission rates
- [ ] Add basic referral display in volunteer dashboard
- [ ] Verify referral codes work correctly

**Week 4**: Admin Interface  
- [ ] Complete admin CRUD for all models
- [ ] Add task review and approval system
- [ ] Test end-to-end volunteer workflow
- [ ] Verify admin can manage everything

### 🔧 Critical Technical Decisions

**Activity Multiplier Implementation**: Use rolling 30-day window with exponential decay as specified in Best Practice Proposal document

**Budget Distribution**: Implement monthly/weekly/daily hybrid model with 85% core allocation and 15% competitive bonus pool

**Commission Calculation**: Auto-credit immediately on sale with admin reversal capability for fraud prevention

**Database Performance**: Add strategic indexes on `user_id`, `level`, `referral_code`, `status`, and date fields

### 🎯 Success Metrics for Phase 1

**Technical Metrics**:
- All migrations run without errors
- All models pass basic CRUD tests
- Component appears in Decidim admin panel
- Volunteer dashboard loads correctly
- Task assignment workflow completes

**Business Logic Metrics**:
- XP awards correctly and levels update
- Referral chains create properly (5 levels)
- Commission rates match specification (10%, 8%, 6%, 4%, 2%)
- Activity multiplier calculations are accurate
- Admin can review and approve tasks

**Integration Metrics**:
- Uses Decidim's native notifications
- Follows Decidim component patterns
- Integrates with existing user system
- Works with Decidim permissions
- Maintains consistent UI/UX

## Support and Documentation

### Key Reference Documents (from Волонтёрская организация folder)
- **Final PROMPT.txt**: Core implementation guidance and Decidim best practices
- **decidim_volunteer_scheduler_spec (5).md**: Complete technical specification 
- **integration_checklist.md**: Phase-by-phase implementation roadmap
- **Best Practice Proposal.txt**: Activity multiplier and budget allocation strategies
- **Phase 1 Goals.txt**: MVP requirements and deliverables

### Additional Resources
- **Decidim Documentation**: https://docs.decidim.org/
- **Component Development Guide**: https://docs.decidim.org/en/develop/guide_development_components  
- **Decidim GitHub**: https://github.com/decidim/decidim
- **Manual Installation Guide**: https://docs.decidim.org/en/develop/install/manual

### Getting Help
- Check existing GitHub issues for common problems
- Review test files for usage examples
- Consult Decidim community forums for platform-specific questions
- Use the test suite as living documentation for expected behavior

### Emergency Troubleshooting
**Module Won't Load**: Check component registration in `lib/decidim/volunteer_scheduler/component.rb`
**Migrations Fail**: Verify foreign key references match existing Decidim tables
**Models Don't Work**: Ensure proper namespacing `Decidim::VolunteerScheduler::`
**Admin Panel Missing**: Check engine registration and menu integration
**Permissions Errors**: Verify authorization logic follows Decidim patterns

---

## ✅ Complete Documentation Analysis Summary

This CLAUDE.md was created based on comprehensive analysis of **ALL** documentation in the "Волонтёрская организация" folder:

### Key Documents Analyzed:
- ✅ **Final PROMPT.txt** - Core implementation guidance and Decidim best practices
- ✅ **decidim_volunteer_scheduler_spec (5).md** - Complete technical specification with 11 phases
- ✅ **integration_checklist.md** - Phase-by-phase implementation roadmap  
- ✅ **Best Practice Proposal.txt** - Activity multiplier and budget allocation strategies
- ✅ **Budget allocation.txt** - Monthly/weekly/daily distribution mechanisms
- ✅ **Referral System.txt** - 5-level commission structure details
- ✅ **Phase 1 Goals.txt** - MVP requirements and success criteria
- ✅ **Structure.txt** - Module organization patterns
- ✅ **Advanced Prompt.txt** - Detailed project requirements
- ✅ **Initial Prompt.txt** - Original concept with WSL2 environment setup
- ✅ **Guide fo checklist.txt** - Step-by-step implementation checklist
- ✅ **One to Unite Them All.txt** - Comprehensive architecture blueprint
- ✅ **More Advanced Prompts.txt** - Implementation details and patterns
- ✅ **First Design.txt** - Initial technical approach with models
- ✅ **First Take.txt** - Original module structure and gemspec
- ✅ **compass_artifact_wf-6eb8a6b9-4328-40f1-a33f-8283c01be503_text_markdown.md** - Decidim 0.30+ specific implementation guide
- ✅ **compass_artifact_wf-ee9b7f75-44bf-4878-a222-72d97d75cbaf_text_markdown.md** - Advanced patterns and community module examples

### Critical Implementation Insights Captured:
1. **Decidim 0.30+ Taxonomy System** - Must use new taxonomy instead of legacy categories
2. **External Module Generation** - Use `decidim --component volunteer_scheduler --external`
3. **PostgreSQL ltree Extension** - For optimal referral hierarchy performance  
4. **ActionCable Integration** - Real-time features with Redis backend
5. **Anti-fraud Detection** - Rate limiting and suspicious activity monitoring
6. **Background Job Architecture** - Sidekiq with dedicated queues for performance
7. **Database Partitioning** - Monthly partitions for high-volume activity data
8. **Community Module Patterns** - Proven approaches from decidim-awesome and others

This documentation provides complete coverage for implementing a production-ready Decidim volunteer scheduler module that leverages all platform capabilities while following established best practices and architectural patterns.

**Next Action**: Begin implementation with Phase 1 foundation using the step-by-step guidance provided above.