# frozen_string_literal: true

module Decidim
  module VolunteerScheduler
    # Permissions class for the volunteer scheduler component
    class Permissions < Decidim::DefaultPermissions
      def permissions
        return permission_action unless user
        return permission_action if permission_action.scope != :public

        case permission_action.subject
        when :task_template
          permission_action.allow! if permission_action.action == :read
        when :task_assignment
          task_assignment_permissions
        when :task_submission
          task_submission_permissions
        when :volunteer_profile
          volunteer_profile_permissions
        when :dashboard
          permission_action.allow! if user.confirmed?
        end

        permission_action
      end

      private

      def task_assignment_permissions
        case permission_action.action
        when :read
          permission_action.allow! if can_read_task_assignment?
        when :create
          permission_action.allow! if can_create_task_assignment?
        when :update
          permission_action.allow! if can_update_task_assignment?
        end
      end

      def task_submission_permissions
        case permission_action.action
        when :create
          permission_action.allow! if can_create_task_submission?
        end
      end

      def volunteer_profile_permissions
        case permission_action.action
        when :read
          permission_action.allow! if can_read_volunteer_profile?
        when :create
          permission_action.allow! if user.confirmed?
        end
      end

      def can_read_task_assignment?
        return true if user_is_admin?
        
        # Allow reading task assignments if user is confirmed (for index page)
        return true if user&.confirmed?
        
        # For specific task assignment, check ownership
        return false unless task_assignment
        task_assignment.assignee.user == user
      end

      def can_create_task_assignment?
        return false unless user&.confirmed?
        
        # For gem distribution: simple permission check
        # Users can create task assignments if they have a confirmed account
        true
      end

      def can_create_task_submission?
        return false unless user&.confirmed?
        
        # Users can submit work for their own task assignments
        task_assign = context[:task_assignment]
        return false unless task_assign
        return false unless task_assign.assignee.user == user
        return false unless task_assign.can_be_submitted?
        
        true
      end

      def can_update_task_assignment?
        return true if user_is_admin?
        return false unless task_assignment
        
        task_assignment.assignee.user == user && task_assignment.can_be_submitted?
      end

      def can_read_volunteer_profile?
        return true if user_is_admin?
        return false unless volunteer_profile
        
        volunteer_profile.user == user
      end

      def user_is_admin?
        return false unless user
        
        # Organization-level admin check
        user.admin?
      end

      # No longer needed for organization-level operation
      # def component_settings_allow_assignment?
      #   return true unless component
      #   
      #   component.current_settings.task_assignment_enabled
      # end

      def task_assignment
        @task_assignment ||= context[:task_assignment]
      end

      def volunteer_profile
        @volunteer_profile ||= context[:volunteer_profile] || user_volunteer_profile
      end

      def user_volunteer_profile
        return nil unless user
        
        # Simple approach for gem distribution
        @user_volunteer_profile ||= user.volunteer_profile
      end

    end
  end
end