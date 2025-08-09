# frozen_string_literal: true

module Decidim
  module VolunteerScheduler
    # Query object to optimize TaskTemplate queries and handle eager loading correctly
    class TaskTemplatesQuery
      def initialize(organization: nil, component: nil)
        @organization = organization
        @component = component
      end

      # Get task templates with optimized includes for admin listing
      def for_admin_list
        base_query
          .order(created_at: :desc)
      end

      # Get task templates for public display (avoid component eager loading)
      def for_public_list
        base_query
          .published
          .order(:level_required, :title)
      end

      # Get task templates available to a specific volunteer
      def available_for_volunteer(volunteer_profile)
        for_public_list
          .for_level(volunteer_profile.level)
          .where.not(
            id: volunteer_profile.task_assignments
                               .pending
                               .select(:task_template_id)
          )
      end

      # Get task templates with assignments for reporting
      def with_assignments_for_reporting
        base_query
          .joins(:task_assignments) # Use joins instead of includes to avoid N+1
          .includes(organization: []) # Add organization includes for performance
          .where(task_assignments: { created_at: 1.month.ago..Time.current })
      end
      
      # Get participatory spaces that need organization info
      def with_participatory_spaces_and_organization
        base_query
          .joins(:component)
          .includes(component: { participatory_space: :organization })
      end

      private

      attr_reader :organization, :component

      def base_query
        query = TaskTemplate.all
        query = query.where(organization: organization) if organization
        query = query.where(component: component) if component
        query
      end
    end
  end
end