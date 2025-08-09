# frozen_string_literal: true

require "decidim/dev/common_rake"

desc "Generates a dummy app for testing"
task test_app: "decidim:generate_external_test_app" do
  ENV["RAILS_ENV"] = "test"
  test_app_path = File.expand_path("spec/decidim_dummy_app", __dir__)
  
  Dir.chdir(test_app_path) do
    system("bundle exec rails decidim_volunteer_scheduler:install:migrations")
    system("bundle exec rails db:migrate")
  end
end

desc "Generates a development app."
task development_app: "decidim:generate_external_development_app"

# Module-specific tasks
namespace :decidim_volunteer_scheduler do
  desc "Install module into development app"
  task :install do
    puts "📦 Installing Decidim Volunteer Scheduler module..."
    
    # Copy migrations
    system("bundle exec rails decidim_volunteer_scheduler:install:migrations")
    
    # Run migrations
    system("bundle exec rails db:migrate")
    
    puts "✅ Module installed successfully!"
  end
  
  desc "Run continuous testing"
  task :test_watch do
    system("bundle exec guard")
  end
  
  desc "Run all tests"
  task :test do
    ENV["RAILS_ENV"] = "test"
    system("bundle exec rspec")
  end
  
  desc "Check code quality"
  task :lint do
    system("bundle exec rubocop -a")
  end
  
  desc "Seed sample data"
  task :seed do
    require_relative "db/seeds"
  end
end

task default: [:lint, :test]
