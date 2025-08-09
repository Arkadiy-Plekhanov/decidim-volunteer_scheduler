# frozen_string_literal: true

require "rails"
require "decidim/core"
require "decidim/volunteer_scheduler/seeds"

module Decidim
  module VolunteerScheduler
    # This is the engine that runs on the public interface of decidim-volunteer_scheduler.
    class Engine < ::Rails::Engine
      isolate_namespace Decidim::VolunteerScheduler

      routes do
        root "dashboard#index"
        
        resources :task_assignments, only: [:index, :show, :create, :update] do
          member do
            patch :submit
          end
          collection do
            post :accept
          end
          
          # Follow-up based submission system
          resources :submissions, only: [:new, :create], controller: "task_submissions"
        end
        
        resources :task_templates, only: [:index] do
          member do
            post :accept, to: "task_assignments#accept"
          end
        end
        
        get "my_dashboard", to: "dashboard#index"
      end

      initializer "decidim_volunteer_scheduler.assets" do |app|
        app.config.assets.precompile += %w[decidim_volunteer_scheduler_manifest.js] if app.config.respond_to?(:assets)
      end

      initializer "decidim_volunteer_scheduler.add_cells_view_paths" do
        Cell::ViewModel.view_paths << File.expand_path("#{Decidim::VolunteerScheduler::Engine.root}/app/cells")
        Cell::ViewModel.view_paths << File.expand_path("#{Decidim::VolunteerScheduler::Engine.root}/app/views")
      end

      # Menu registration disabled temporarily - will be added properly per component
      # TODO: Implement proper component-level menu integration
      # The global menu approach was causing CSRF token conflicts

      initializer "VolunteerScheduler.webpacker.assets_path" do
        Decidim.register_assets_path File.expand_path("app/packs", root)
      end

      # Register events for notifications  
      initializer "decidim_volunteer_scheduler.events", after: "decidim.mount_routes" do
        Rails.application.config.to_prepare do
          next unless defined?(Decidim::EventsManager)
          
          # Only register if EventsManager is available
          Decidim::EventsManager.subscribe("decidim.volunteer_scheduler.task_approved") do |event_name, data|
            Decidim::VolunteerScheduler::TaskApprovedEvent.publish(
              event_name: event_name,
              resource: data[:task_assignment],
              affected_users: [data[:task_assignment].assignee.user]
            )
          end
          
          Decidim::EventsManager.subscribe("decidim.volunteer_scheduler.task_rejected") do |event_name, data|
            Decidim::VolunteerScheduler::TaskRejectedEvent.publish(
              event_name: event_name,
              resource: data[:task_assignment],
              affected_users: [data[:task_assignment].assignee.user]
            )
          end
        end
      rescue NameError
        # EventsManager not available yet, skip
      end

      # Register icons
      initializer "decidim_volunteer_scheduler.register_icons", after: "decidim_core.register_icons" do
        Decidim.icons.register(name: "user-heart-line", icon: "user-heart-line", category: "system", description: "Volunteer user icon", engine: :volunteer_scheduler)
      end

      # Register content blocks
      initializer "decidim_volunteer_scheduler.homepage_content_blocks" do
        Decidim.content_blocks.register(:homepage, :volunteer_scheduler) do |content_block|
          content_block.cell = "decidim/volunteer_scheduler/content_blocks/volunteer_scheduler_block"
          content_block.public_name_key = "decidim.volunteer_scheduler.content_blocks.volunteer_scheduler.name"
          content_block.default!
        end
      end

      # Register menus
      initializer "decidim_volunteer_scheduler.menu" do
        Decidim.menu :menu do |menu|
          menu.add_item :volunteer_scheduler,
                        I18n.t("decidim.volunteer_scheduler.menu.volunteer_dashboard"),
                        "/volunteer_scheduler",
                        position: 4.5,
                        if: proc { current_user&.confirmed? },
                        active: :inclusive,
                        icon_name: "user-heart-line"
        end

        Decidim.menu :user_menu do |menu|
          menu.add_item :volunteer_dashboard,
                        I18n.t("decidim.volunteer_scheduler.menu.volunteer_dashboard"),
                        "/volunteer_scheduler",
                        position: 2.5,
                        if: proc { current_user&.confirmed? }
        end
      end

      # Extend Decidim::User with volunteer profile functionality
      config.to_prepare do
        Decidim::User.include Decidim::VolunteerScheduler::UserExtension
      end
    end
  end
end
