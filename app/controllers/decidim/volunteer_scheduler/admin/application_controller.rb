# frozen_string_literal: true

module Decidim
  module VolunteerScheduler
    module Admin
      # Base controller for admin interface
      class ApplicationController < Decidim::Admin::ApplicationController
        include Decidim::VolunteerScheduler::Admin::ApplicationHelper
        
        layout "decidim/admin/users"

        private

        def ensure_admin_permissions
          enforce_permission_to :manage, :admin_dashboard
        end
      end
    end
  end
end
