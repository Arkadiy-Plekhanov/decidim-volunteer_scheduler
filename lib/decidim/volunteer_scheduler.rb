# frozen_string_literal: true

require "decidim/volunteer_scheduler/admin"
require "decidim/volunteer_scheduler/engine"
require "decidim/volunteer_scheduler/admin_engine"
# require "decidim/volunteer_scheduler/component" # Temporarily disabled - using as global engine only

module Decidim
  # This namespace holds the logic of the `VolunteerScheduler` component. This component
  # allows users to create volunteer_scheduler in a participatory space.
  module VolunteerScheduler
  end
end

# Register the global engine with Decidim for automatic installation
Decidim.register_global_engine(
  :decidim_volunteer_scheduler,
  Decidim::VolunteerScheduler::Engine,
  at: "/volunteer_scheduler"
)
