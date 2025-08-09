# frozen_string_literal: true

module Decidim
  module VolunteerScheduler
    module Admin
      # Custom helpers for the admin interface
      module ApplicationHelper
        # Returns CSS class for task template status badges
        def template_status_class(template)
          case template.status
          when "draft"
            "secondary"
          when "published"
            "success"
          when "archived"
            "alert"
          else
            "secondary"
          end
        end
      end
    end
  end
end