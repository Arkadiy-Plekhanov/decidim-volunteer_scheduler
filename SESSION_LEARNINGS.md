# Session Learnings: Decidim Volunteer Scheduler Development

## Overview
This document captures all key learnings, solutions, and patterns discovered during the development of the decidim-volunteer_scheduler module. This serves as a comprehensive reference for future Decidim module development.

---

## Table of Contents
1. [Critical Technical Discoveries](#critical-technical-discoveries)
2. [Decidim Architecture Patterns](#decidim-architecture-patterns)
3. [Common Issues and Solutions](#common-issues-and-solutions)
4. [Development Workflow Best Practices](#development-workflow-best-practices)
5. [Module Integration Patterns](#module-integration-patterns)
6. [Testing and Quality Assurance](#testing-and-quality-assurance)
7. [Git and Repository Management](#git-and-repository-management)

---

## Critical Technical Discoveries

### 1. Decidim Module Registration Patterns

**Key Learning**: Decidim modules require specific registration patterns that differ from standard Rails engines.

#### ✅ Correct Pattern (Engine-based Registration):
```ruby
# lib/decidim/volunteer_scheduler/engine.rb
initializer "decidim_volunteer_scheduler.register_icons", after: "decidim_core.register_icons" do
  Decidim.icons.register(name: "user-heart-line", icon: "user-heart-line", category: "system", description: "Volunteer user icon", engine: :volunteer_scheduler)
end

initializer "decidim_volunteer_scheduler.homepage_content_blocks" do
  Decidim.content_blocks.register(:homepage, :volunteer_scheduler) do |content_block|
    content_block.cell = "decidim/volunteer_scheduler/content_blocks/volunteer_scheduler_block"
    content_block.public_name_key = "decidim.volunteer_scheduler.content_blocks.volunteer_scheduler.name"
    content_block.default!
  end
end

initializer "decidim_volunteer_scheduler.menu" do
  Decidim.menu :menu do |menu|
    menu.add_item :volunteer_scheduler,
                  I18n.t("decidim.volunteer_scheduler.menu.volunteer_dashboard"),
                  "/volunteer_scheduler",
                  position: 4.5,
                  if: proc { current_user&.confirmed? },
                  active: :inclusive,
                  icon_name: "user-heart-line"
  end
end
```

#### ❌ Incorrect Pattern (Config Initializers):
```ruby
# config/initializers/volunteer_scheduler_menu.rb - DON'T DO THIS
Rails.application.config.after_initialize do
  Decidim.menu :menu do |menu|
    # This causes duplicate registrations and timing issues
  end
end
```

**Why**: Engine initializers ensure proper loading order and prevent duplicate registrations.

### 2. Decidim Content Block API

**Key Learning**: Decidim 0.30+ uses `default!` method, not `default_priority=`.

#### ✅ Correct API:
```ruby
Decidim.content_blocks.register(:homepage, :volunteer_scheduler) do |content_block|
  content_block.cell = "decidim/volunteer_scheduler/content_blocks/volunteer_scheduler_block"
  content_block.public_name_key = "decidim.volunteer_scheduler.content_blocks.volunteer_scheduler.name"
  content_block.default!  # ← This is correct
end
```

#### ❌ Incorrect API:
```ruby
content_block.default_priority = 10  # ← This method doesn't exist
```

### 3. Decidim Icon System

**Key Learning**: Decidim has a strict icon registry system. Custom icons must be registered properly.

#### Available Core Icons Found:
- `user-smile-line`, `account-circle-line` (user-related)
- `user-settings-line` (admin/settings)
- `information-line`, `alert-line`, `check-line`
- `arrow-right-line`, `home-2-line`, `global-line`

#### Custom Icon Registration:
```ruby
Decidim.icons.register(name: "user-heart-line", icon: "user-heart-line", category: "system", description: "Volunteer user icon", engine: :volunteer_scheduler)
```

### 4. Organization-Level vs Component-Level Architecture

**Key Learning**: Our volunteer scheduler works as organization-level functionality, not component-level.

#### Architecture Decision:
- **Organization-Level**: Volunteer profiles, referral systems, global XP tracking
- **Component-Level**: Individual task templates within participatory processes
- **Hybrid Approach**: Models are organization-scoped, but tasks can be component-scoped

---

## Decidim Architecture Patterns

### 1. Proper Gem Structure

**Essential Files for Decidim Gems**:
```
decidim-module-name/
├── decidim-module-name.gemspec     # Gem specification
├── lib/
│   ├── decidim-module-name.rb      # Main require file
│   └── decidim/
│       └── module_name/
│           ├── version.rb          # Version constants
│           ├── engine.rb           # Main engine
│           ├── admin_engine.rb     # Admin interface
│           └── component.rb        # Component registration
├── app/                            # Standard Rails app structure
├── config/locales/                 # Translations
├── db/migrate/                     # Migrations
└── spec/                          # Tests
```

### 2. Engine Configuration Pattern

**Complete Engine Structure**:
```ruby
module Decidim
  module ModuleName
    class Engine < ::Rails::Engine
      isolate_namespace Decidim::ModuleName

      routes do
        # Define routes here
      end

      # Icon registration
      initializer "decidim_module.register_icons", after: "decidim_core.register_icons" do
        # Register custom icons
      end

      # Content block registration  
      initializer "decidim_module.homepage_content_blocks" do
        # Register content blocks
      end

      # Menu registration
      initializer "decidim_module.menu" do
        # Register menu items
      end

      # Asset configuration
      initializer "decidim_module.assets" do |app|
        app.config.assets.precompile += %w[decidim_module_manifest.js]
      end

      # User extensions
      config.to_prepare do
        Decidim::User.include Decidim::ModuleName::UserExtension
      end
    end
  end
end
```

### 3. Gemspec Best Practices

**Critical Dependencies**:
```ruby
s.add_dependency "decidim-core", Decidim::ModuleName::DECIDIM_VERSION
s.add_dependency "decidim-admin", Decidim::ModuleName::DECIDIM_VERSION
s.add_dependency "decidim-api", Decidim::ModuleName::DECIDIM_VERSION

# For background jobs
s.add_dependency "sidekiq", ">= 7.0"
s.add_dependency "sidekiq-cron", ">= 1.9"
```

---

## Common Issues and Solutions

### 1. Route Not Found Errors

**Issue**: `No route matches [GET] "/volunteer_scheduler"`

**Root Cause**: Module not properly loaded as gem in host application.

**Solution**: 
1. Ensure module is in development_app Gemfile:
   ```ruby
   gem "decidim-volunteer_scheduler", path: "../../decidim-volunteer_scheduler"
   ```
2. Run `bundle install`
3. Install migrations: `rails decidim_volunteer_scheduler:install:migrations`
4. Run migrations: `rails db:migrate`

### 2. Icon Errors

**Issue**: `Icon user not found. Register it with...`

**Root Causes**: 
- Using non-existent icon names
- Registering icons in wrong initializer order
- Duplicate registrations

**Solutions**:
1. Use existing Decidim icons or register custom ones properly
2. Use `after: "decidim_core.register_icons"` in initializer
3. Check for duplicate registrations in multiple locations

### 3. Content Block Not Appearing

**Issue**: Content blocks don't appear in admin panel.

**Root Causes**:
- Wrong registration method (`default_priority=` vs `default!`)
- Registration in config/initializers instead of engine
- Missing translation keys

**Solutions**:
1. Use `content_block.default!` method
2. Register in engine initializer
3. Ensure all translation keys exist

### 4. Menu Items Not Showing

**Issue**: Menu items don't appear in navigation.

**Root Causes**:
- Using non-existent icons
- Wrong conditional logic in `if:` proc
- Duplicate registrations causing conflicts

**Solutions**:
1. Remove icon references or use valid icons
2. Simplify conditional logic
3. Register only in engine, not config/initializers

---

## Development Workflow Best Practices

### 1. Research-First Approach

**Critical Learning**: Always research Decidim patterns before implementing.

**Process**:
1. Study official Decidim documentation
2. Examine existing successful modules (decidim-awesome, decidim-initiatives)
3. Look at core Decidim code for patterns
4. Implement using established patterns
5. Test thoroughly

### 2. Debugging Workflow

**When Something Doesn't Work**:
1. Check Rails environment loads: `rails runner "puts 'OK'"`
2. Check routes: `rails routes | grep volunteer`
3. Check registrations: Look for duplicate or conflicting registrations
4. Check logs for specific error messages
5. Research the exact error in Decidim codebase

### 3. Testing Strategy

**Levels of Testing**:
1. **Unit Tests**: Models, services, commands
2. **Integration Tests**: Controllers, forms
3. **System Tests**: End-to-end user workflows
4. **Manual Testing**: Real browser testing with seed data

### 4. Migration Management

**Best Practices**:
- Use sequential numbering (001_, 002_, etc.)
- Include proper foreign key constraints
- Add indexes for frequently queried fields
- Use Decidim's migration patterns
- Test rollbacks

---

## Module Integration Patterns

### 1. User Extensions

**Pattern for Extending Decidim::User**:
```ruby
# app/models/concerns/decidim/volunteer_scheduler/user_extension.rb
module Decidim
  module VolunteerScheduler
    module UserExtension
      extend ActiveSupport::Concern

      included do
        has_one :volunteer_profile, 
                class_name: "Decidim::VolunteerScheduler::VolunteerProfile",
                dependent: :destroy

        after_create :create_volunteer_profile
      end

      private

      def create_volunteer_profile
        return if volunteer_profile.present?
        
        Decidim::VolunteerScheduler::VolunteerProfile.create!(
          user: self,
          organization: organization,
          level: 1,
          total_xp: 0,
          referral_code: generate_referral_code
        )
      end
    end
  end
end
```

### 2. Organization Scoping

**Pattern for Organization-Level Data**:
```ruby
class VolunteerProfile < ApplicationRecord
  belongs_to :organization, 
             foreign_key: "decidim_organization_id",
             class_name: "Decidim::Organization"
             
  scope :for_organization, ->(org) { where(organization: org) }
end
```

### 3. Background Jobs

**Pattern for Decidim-Compatible Jobs**:
```ruby
class ActivityMultiplierJob < ApplicationJob
  queue_as :default

  def perform(organization_id)
    organization = Decidim::Organization.find(organization_id)
    
    # Process organization-scoped data
    organization.volunteer_profiles.find_each do |profile|
      # Update multipliers
    end
  end
end
```

---

## Testing and Quality Assurance

### 1. Factory Patterns

**FactoryBot Setup for Decidim**:
```ruby
FactoryBot.define do
  factory :volunteer_profile, class: "Decidim::VolunteerScheduler::VolunteerProfile" do
    user { create :user, :confirmed }
    organization { user.organization }
    level { 1 }
    total_xp { 0 }
    referral_code { SecureRandom.alphanumeric(8).upcase }
  end
end
```

### 2. System Testing

**End-to-End Test Structure**:
```ruby
require "rails_helper"

describe "Volunteer Workflow", type: :system do
  let(:organization) { create :organization }
  let(:user) { create :user, :confirmed, organization: organization }
  
  before do
    switch_to_host(organization.host)
    login_as user, scope: :user
  end

  it "allows volunteers to access dashboard" do
    visit decidim_volunteer_scheduler.root_path
    expect(page).to have_content("Volunteer Dashboard")
  end
end
```

### 3. Seed Data Strategy

**Comprehensive Seed Data**:
```ruby
# db/seeds.rb
organization = Decidim::Organization.first
admin = organization.admins.first

# Create volunteer profiles for testing
%w[volunteer1 volunteer2 volunteer3].each_with_index do |email, index|
  user = Decidim::User.find_or_create_by!(
    email: "#{email}@example.org",
    organization: organization
  ) do |u|
    u.name = email.humanize
    u.nickname = email
    u.password = "decidim123456789"
    u.confirmed_at = Time.current
  end

  user.create_volunteer_profile! if user.volunteer_profile.blank?
end
```

---

## Git and Repository Management

### 1. GitHub Authentication

**Modern GitHub Authentication**:
- ❌ **Password authentication**: No longer supported
- ✅ **Personal Access Token (PAT)**: Use for HTTPS
- ✅ **SSH keys**: Most secure for regular use

**PAT Setup**:
1. GitHub Settings → Developer Settings → Personal Access Tokens
2. Generate token with `repo` scope
3. Use as password in git commands

**Embedded Token in Remote**:
```bash
git remote set-url origin https://username:PAT_TOKEN@github.com/username/repo.git
```

### 2. Gitignore for Decidim Modules

**Essential Exclusions**:
```gitignore
# Ruby/Rails
*.log
/tmp
/coverage
Gemfile.lock

# Decidim specific
/public/uploads
/public/decidim-packs
dump.rdb

# Development files
test_request.json
*.sqlite3*

# GitHub workflows (if PAT lacks workflow scope)
.github/workflows/
```

### 3. Commit Message Patterns

**Effective Commit Messages**:
```
feat: Add XP-based volunteer progression system
fix: Resolve icon registration timing issue  
docs: Update installation instructions
refactor: Optimize referral chain queries
test: Add system tests for task assignment workflow
```

---

## Key Success Metrics

### What Worked Well:
1. **Research-first approach**: Studying existing modules saved significant time
2. **Engine-based registration**: Proper Decidim patterns prevented many issues  
3. **Organization-level architecture**: Correct scoping for volunteer management
4. **Comprehensive testing**: Early testing caught integration issues
5. **Proper gem structure**: Following Decidim conventions enabled easy installation

### What to Avoid:
1. **Config initializer registrations**: Caused duplicate registration errors
2. **Wrong API methods**: Using deprecated or non-existent methods
3. **Custom icons without registration**: Led to runtime errors
4. **Component-level for organization data**: Wrong architectural choice
5. **Password authentication**: GitHub no longer supports it

---

## Future Development Guidelines

### 1. Before Starting Any Decidim Module:
1. Study decidim-awesome module structure
2. Read official Decidim component development guide
3. Examine 2-3 existing successful community modules
4. Plan architecture (organization vs component level)
5. Set up proper testing environment first

### 2. During Development:
1. Test early and often in real Decidim environment
2. Use proper Decidim patterns from the start
3. Create comprehensive seed data for testing
4. Follow Decidim naming and structure conventions
5. Document unusual decisions and workarounds

### 3. Before Release:
1. Test installation in fresh Decidim app
2. Verify all routes work correctly  
3. Check admin interfaces are accessible
4. Validate translations are complete
5. Ensure gem can be installed via Gemfile

---

## Technical Implementation Notes

### Database Schema Considerations:
- **Foreign Keys**: Always use proper Decidim foreign key patterns
- **Indexing**: Add indexes on frequently queried organization and user fields
- **Namespacing**: Use proper table name prefixes (`decidim_volunteer_scheduler_`)
- **Migrations**: Sequential numbering prevents conflicts

### Performance Optimizations Applied:
- **Counter Caches**: Added for task assignment counts
- **Eager Loading**: Optimized N+1 queries in dashboards
- **Scoped Queries**: Organization-level scoping for all data access
- **Background Jobs**: Heavy operations moved to background processing

### Security Measures:
- **Authorization**: Proper permission checks at all levels
- **Data Scoping**: All queries scoped to current organization
- **Input Validation**: Comprehensive form validations
- **CSRF Protection**: Standard Rails CSRF tokens used

---

## Conclusion

This session demonstrated that successful Decidim module development requires:

1. **Deep understanding** of Decidim architecture patterns
2. **Careful research** before implementation
3. **Proper testing** in realistic environments  
4. **Following established conventions** rather than reinventing
5. **Iterative development** with frequent validation

The decidim-volunteer_scheduler module serves as a comprehensive example of these principles applied successfully, resulting in a production-ready Decidim extension that properly integrates with the platform's ecosystem.

---

*Document Created: [Current Date]*  
*Module Version: 0.1.0*  
*Decidim Version: 0.31.0.dev*  
*Total Development Time: Multiple intensive sessions*  
*Final Status: ✅ Production Ready & GitHub Published*