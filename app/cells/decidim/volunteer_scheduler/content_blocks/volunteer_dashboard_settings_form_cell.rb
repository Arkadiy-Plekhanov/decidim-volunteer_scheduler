# frozen_string_literal: true

module Decidim
  module VolunteerScheduler
    module ContentBlocks
      class VolunteerDashboardSettingsFormCell < Decidim::ViewModel
        def show
          # No settings needed for now, return empty form
          ""
        end
      end
    end
  end
end