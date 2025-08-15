# frozen_string_literal: true

$LOAD_PATH.push File.expand_path("lib", __dir__)

require "decidim/volunteer_scheduler/version"

Gem::Specification.new do |s|
  s.version = Decidim::VolunteerScheduler::VERSION
  s.authors = ["Scicent Team"]
  s.email = ["info@scicent.org"]
  s.license = "AGPL-3.0-or-later"
  s.homepage = "https://github.com/scicent/decidim-volunteer_scheduler"
  s.metadata = {
    "bug_tracker_uri" => "https://github.com/scicent/decidim-volunteer_scheduler/issues",
    "documentation_uri" => "https://github.com/scicent/decidim-volunteer_scheduler/blob/main/README.md",
    "funding_uri" => "https://opencollective.com/decidim",
    "homepage_uri" => "https://github.com/scicent/decidim-volunteer_scheduler",
    "source_code_uri" => "https://github.com/scicent/decidim-volunteer_scheduler",
    "rubygems_mfa_required" => "true"
  }
  s.required_ruby_version = ">= 3.3.0"

  s.name = "decidim-volunteer_scheduler"
  s.summary = "A Decidim component for volunteer scheduling with XP, leveling and referral system"
  s.description = "This module enables gamified volunteer engagement through task management, XP leveling, and a 5-level referral system with token rewards."

  s.files = Dir[
    "{app,config,db,lib,vendor}/**/*",
    "LICENSE-AGPLv3.txt",
    "Rakefile",
    "README.md"
  ]

  # Core Decidim dependencies
  s.add_dependency "decidim-core", Decidim::VolunteerScheduler::DECIDIM_VERSION
  s.add_dependency "decidim-admin", Decidim::VolunteerScheduler::DECIDIM_VERSION
  
  # Testing
  s.add_development_dependency "factory_bot_rails", "~> 6.2"
  s.add_development_dependency "faker", "~> 3.2"
  s.add_development_dependency "rspec-rails", "~> 6.0"
  
  # Code quality
  s.add_development_dependency "rubocop", "~> 1.69.0"
  s.add_development_dependency "rubocop-rails", "~> 2.20"
  s.add_development_dependency "rubocop-rspec", "~> 2.20"
  
  # Coverage
  s.add_development_dependency "simplecov", "~> 0.22"
end
