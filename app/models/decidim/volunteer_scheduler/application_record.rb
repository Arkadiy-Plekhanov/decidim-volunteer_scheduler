# frozen_string_literal: true

module Decidim
  module VolunteerScheduler
    # Base class for all VolunteerScheduler models.
    class ApplicationRecord < Decidim::ApplicationRecord
      self.abstract_class = true
    end
  end
end
