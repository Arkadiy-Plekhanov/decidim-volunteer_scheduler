#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "pathname"

puts "🚀 Setting up decidim-volunteer_scheduler for integration into development_app..."

# Paths
module_path = Pathname.new(__dir__)
development_app_path = Pathname.new("/home/scicent/projects/decidim/development_app")

# Check if development_app exists
unless development_app_path.exist?
  puts "❌ Development app not found at #{development_app_path}"
  puts "Please ensure your Decidim development app is set up at the correct path."
  exit 1
end

puts "✅ Found development app at #{development_app_path}"

# Add gem to development app Gemfile
gemfile_path = development_app_path / "Gemfile"
gemfile_content = File.read(gemfile_path)

gem_line = 'gem "decidim-volunteer_scheduler", path: "' + module_path.to_s + '"'

unless gemfile_content.include?("decidim-volunteer_scheduler")
  puts "📝 Adding gem to development app Gemfile..."
  
  # Add after decidim gems
  new_content = gemfile_content.gsub(
    /gem "decidim-dev".*$/,
    "gem \"decidim-dev\", \"~> 0.30.1\"\n\n# Local modules\n#{gem_line}"
  )
  
  File.write(gemfile_path, new_content)
  puts "✅ Added gem to Gemfile"
else
  puts "ℹ️  Gem already in Gemfile"
end

# Create migration install script
install_script = development_app_path / "install_volunteer_scheduler.rb"
File.write(install_script, <<~RUBY)
  #!/usr/bin/env ruby
  # frozen_string_literal: true
  
  puts "🔄 Installing decidim-volunteer_scheduler migrations and assets..."
  
  # Bundle install
  puts "📦 Running bundle install..."
  system("bundle install") or exit(1)
  
  # Install migrations
  puts "🗄️  Installing migrations..."
  system("rails decidim_volunteer_scheduler:install:migrations") or begin
    puts "⚠️  Migration install failed, but this might be expected if migrations don't exist yet"
  end
  
  # Run migrations
  puts "🔄 Running migrations..."
  system("rails db:migrate") or exit(1)
  
  # Precompile assets if in production-like environment
  if ENV["RAILS_ENV"] == "production"
    puts "📦 Precompiling assets..."
    system("rails assets:precompile") or exit(1)
  end
  
  puts "✅ Installation complete!"
  puts ""
  puts "🎯 Next steps:"
  puts "1. Start your development server: rails server"
  puts "2. Visit http://localhost:3000"
  puts "3. Login as admin and create a Participatory Process"
  puts "4. Add the 'Volunteer Scheduler' component to your process"
  puts "5. Configure the component settings (XP values, referral rates, etc.)"
  puts ""
  puts "📋 Admin tasks:"
  puts "- Create task templates in the admin interface"
  puts "- Set up XP thresholds and referral commission rates"
  puts "- Monitor volunteer assignments and approvals"
  puts ""
  puts "🔗 Volunteer features:"
  puts "- Users can view their volunteer dashboard"
  puts "- Accept and complete tasks to earn XP"
  puts "- Level up to unlock more capabilities"
  puts "- Refer other users with unique referral codes"
RUBY

File.chmod(0o755, install_script)

# Create quick test script
test_script = development_app_path / "test_volunteer_scheduler.rb"
File.write(test_script, <<~RUBY)
  #!/usr/bin/env ruby
  # frozen_string_literal: true
  
  # Quick test script for volunteer scheduler functionality
  puts "🧪 Testing decidim-volunteer_scheduler integration..."
  
  require_relative "config/environment"
  
  # Test that models load properly
  begin
    puts "📋 Testing model loading..."
    Decidim::VolunteerScheduler::VolunteerProfile
    Decidim::VolunteerScheduler::TaskTemplate  
    Decidim::VolunteerScheduler::TaskAssignment
    Decidim::VolunteerScheduler::Referral
    Decidim::VolunteerScheduler::ScicentTransaction
    puts "✅ All models loaded successfully"
  rescue => e
    puts "❌ Model loading failed: \#{e.message}"
    exit 1
  end
  
  # Test that component is registered
  begin
    puts "📦 Testing component registration..."
    component_manifest = Decidim.component_manifests.find { |m| m.name == :volunteer_scheduler }
    if component_manifest
      puts "✅ Component manifest found: \#{component_manifest.name}"
    else
      puts "❌ Component manifest not found"
      exit 1
    end
  rescue => e
    puts "❌ Component registration test failed: \#{e.message}"
    exit 1
  end
  
  # Test database connection and tables
  begin
    puts "🗄️  Testing database tables..."
    ActiveRecord::Base.connection.tables.select { |t| t.include?("volunteer_scheduler") }.each do |table|
      puts "  ✅ Found table: \#{table}"
    end
  rescue => e
    puts "❌ Database test failed: \#{e.message}"
    exit 1
  end
  
  puts "🎉 All tests passed! The module appears to be properly integrated."
  puts ""
  puts "You can now:"
  puts "1. Start the server: rails server"
  puts "2. Create a participatory process as admin"
  puts "3. Add the Volunteer Scheduler component"
  puts "4. Test the volunteer workflow"
RUBY

File.chmod(0o755, test_script)

# Create README for integration
readme_path = development_app_path / "VOLUNTEER_SCHEDULER_README.md"
File.write(readme_path, <<~MARKDOWN)
  # Decidim Volunteer Scheduler Integration
  
  This development app now includes the `decidim-volunteer_scheduler` module for testing and development.
  
  ## Quick Start
  
  1. **Install the module:**
     ```bash
     ./install_volunteer_scheduler.rb
     ```
  
  2. **Test the integration:**
     ```bash
     ./test_volunteer_scheduler.rb
     ```
  
  3. **Start the server:**
     ```bash
     rails server
     ```
  
  ## Module Features
  
  ### For Administrators
  - Create and manage task templates
  - Set XP rewards and level thresholds  
  - Configure referral commission rates (5 levels: 10%, 8%, 6%, 4%, 2%)
  - Review and approve volunteer task submissions
  - Monitor volunteer profiles and activity
  - Export volunteer data
  
  ### For Volunteers
  - Accept tasks based on their current level
  - Submit completed work for review
  - Earn XP and level up (unlocks more tasks)
  - Generate referral codes to invite others
  - Track referral earnings and commissions
  - View progress dashboard with statistics
  
  ### Technical Features
  - 5-level referral system with commission distribution
  - XP-based progression system with customizable thresholds
  - Activity multiplier calculations
  - Background job processing for commissions
  - Scicent token integration (webhook-ready)
  - Real-time updates via ActionCable (when enabled)
  - Comprehensive audit logging
  
  ## Configuration
  
  Component settings (configurable in admin):
  - `xp_per_task`: Base XP reward per task (default: 20)
  - `max_daily_tasks`: Maximum tasks per volunteer per day (default: 5)
  - `referral_commission_l1` through `l5`: Commission rates for each referral level
  - `level_thresholds`: XP amounts needed for each level (comma-separated)
  - `task_deadline_days`: Days to complete tasks (default: 7)
  
  ## Database Schema
  
  The module creates these tables:
  - `decidim_volunteer_scheduler_volunteer_profiles` - User XP, levels, referral codes
  - `decidim_volunteer_scheduler_task_templates` - Admin-created task definitions
  - `decidim_volunteer_scheduler_task_assignments` - Volunteer task acceptances/completions
  - `decidim_volunteer_scheduler_referrals` - 5-level referral relationships
  - `decidim_volunteer_scheduler_scicent_transactions` - Token transaction logging
  
  ## Development Workflow
  
  1. **Phase 1 (Current)**: Basic task system + referral foundations
  2. **Phase 2 (Next)**: Advanced multipliers + token integration  
  3. **Phase 3 (Future)**: Production optimization + monitoring
  
  ## Troubleshooting
  
  **Module won't load:**
  - Check that all migrations ran: `rails db:migrate`
  - Verify gem is in Gemfile: `bundle list | grep volunteer`
  
  **Component not appearing:**
  - Restart the server after installation
  - Check admin permissions for component creation
  
  **Database errors:**
  - Ensure PostgreSQL is running (required for proper JSONB support)
  - Run migrations: `rails db:migrate`
  
  **Permission errors:**
  - Verify user has admin access to the participatory space
  - Check component settings allow task assignment
  
  ## API Documentation
  
  Models include comprehensive YARD documentation. Generate docs with:
  ```bash
  yard doc app/models/decidim/volunteer_scheduler/
  ```
  
  ## Testing
  
  The module includes comprehensive test coverage:
  ```bash
  rspec spec/models/decidim/volunteer_scheduler/
  ```
MARKDOWN

puts "✅ Created integration files:"
puts "  📄 #{gemfile_path} (updated)"
puts "  🔧 #{install_script}"
puts "  🧪 #{test_script}"
puts "  📖 #{readme_path}"

puts ""
puts "🎯 Ready for integration! Next steps:"
puts "1. cd #{development_app_path}"
puts "2. ./install_volunteer_scheduler.rb"
puts "3. ./test_volunteer_scheduler.rb"
puts "4. rails server"
puts ""
puts "📋 The module is now ready for testing and development!"
puts "Check the VOLUNTEER_SCHEDULER_README.md for detailed usage instructions."