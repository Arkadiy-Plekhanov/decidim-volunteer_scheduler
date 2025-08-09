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
          permission_action.allow! if action?(:read)
        when :task_assignment
          task_assignment_permissions
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
        return false unless task_assignment
        
        task_assignment.assignee.user == user
      end

      def can_create_task_assignment?
        return false unless user.confirmed?
        return false unless component_settings_allow_assignment?
        
        volunteer_profile = user_volunteer_profile
        return false unless volunteer_profile
        
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
        
        user.admin? || 
        (component && user.role_for(component.participatory_space) == "admin")
      end

      def component_settings_allow_assignment?
        return true unless component
        
        component.current_settings.task_assignment_enabled
      end

      def task_assignment
        @task_assignment ||= context[:task_assignment]
      end

      def volunteer_profile
        @volunteer_profile ||= context[:volunteer_profile] || user_volunteer_profile
      end

      def user_volunteer_profile
        return nil unless user
        
        @user_volunteer_profile ||= Decidim::VolunteerScheduler::VolunteerProfile
                                      .find_by(user: user, organization: current_organization)
      end

      def action?(expected_action)
        permission_action.action == expected_action
      end
    end
  end
end