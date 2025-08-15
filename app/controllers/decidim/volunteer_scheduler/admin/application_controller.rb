# frozen_string_literal: true

module Decidim
  module VolunteerScheduler
    module Admin
      # Base controller for admin interface
      class ApplicationController < Decidim::Admin::ApplicationController
        helper_method :collection
        
        before_action :ensure_admin_user

        private

        def ensure_admin_user
          redirect_to decidim.new_user_session_path unless current_user&.admin?
        end

        def collection
          @collection ||= paginated_collection
        end

        def paginated_collection
          raise NotImplementedError, "Subclasses must implement #paginated_collection"
        end
      end
    end
  end
end
