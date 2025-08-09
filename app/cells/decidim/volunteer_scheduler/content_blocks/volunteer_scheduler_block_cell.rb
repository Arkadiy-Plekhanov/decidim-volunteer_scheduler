# frozen_string_literal: true

module Decidim
  module VolunteerScheduler
    module ContentBlocks
      # Cell for rendering the volunteer scheduler content block on the homepage
      class VolunteerSchedulerBlockCell < Decidim::ViewModel
        delegate :current_organization, to: :controller
        
        def show
          return unless current_user
          render
        end

        private

        def current_volunteer_profile
          return nil unless current_user&.confirmed?
          @current_volunteer_profile ||= current_user.volunteer_profile
        end

        def stats
          return {} unless current_volunteer_profile

          {
            level: current_volunteer_profile.level,
            total_xp: current_volunteer_profile.total_xp,
            available_tasks_count: available_tasks_count,
            pending_assignments_count: pending_assignments_count
          }
        end

        def available_tasks_count
          @available_tasks_count ||= Decidim::VolunteerScheduler::TaskTemplate
                                       .where(organization: current_organization)
                                       .published
                                       .where("level_required <= ?", current_volunteer_profile.level)
                                       .count
        end

        def pending_assignments_count
          @pending_assignments_count ||= current_volunteer_profile
                                           .task_assignments
                                           .where(status: [:pending, :in_progress])
                                           .count
        end

        def dashboard_path
          decidim_volunteer_scheduler.root_path
        end

        def volunteer_scheduler_enabled?
          current_organization.present?
        end
      end
    end
  end
end