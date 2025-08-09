# frozen_string_literal: true

module Decidim
  module VolunteerScheduler
    # This is the engine that runs on the admin interface of `decidim-volunteer_scheduler`.
    class AdminEngine < ::Rails::Engine
      isolate_namespace Decidim::VolunteerScheduler::Admin

      paths["db/migrate"] = nil
      paths["lib/tasks"] = nil

      routes do
        resources :task_templates do
          member do
            put :publish
            put :unpublish
          end
        end
        
        resources :task_assignments, only: [:index, :show, :update] do
          collection do
            patch :bulk_approve
            patch :bulk_reject
          end
        end
        
        resources :volunteer_profiles, only: [:index, :show]
        
        root to: "task_templates#index"
      end

      initializer "decidim_volunteer_scheduler.admin_assets" do |app|
        app.config.assets.precompile += %w[decidim_volunteer_scheduler_admin_manifest.js] if app.config.respond_to?(:assets)
      end

      initializer "decidim_volunteer_scheduler_admin.mount_routes" do |_app|
        Decidim::Core::Engine.routes do
          mount Decidim::VolunteerScheduler::AdminEngine, at: "/admin/volunteer_scheduler", as: "decidim_admin_volunteer_scheduler"
        end
      end

      initializer "decidim_volunteer_scheduler.admin_menu" do
        Decidim.menu :admin_menu do |menu|
          menu.item I18n.t("menu.volunteer_scheduler", scope: "decidim.volunteer_scheduler.admin"),
                    decidim_admin_volunteer_scheduler.root_path
        end
      end

      def load_seed
        nil
      end
    end
  end
end
