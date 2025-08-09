# frozen_string_literal: true

module Decidim
  module VolunteerScheduler
    module Admin
      class Permissions < Decidim::DefaultPermissions
        def permissions
          return permission_action unless user
          return permission_action unless permission_action.scope == :admin

          case permission_action.subject
          when :task_template
            admin_task_template_permissions
          when :task_assignment
            admin_task_assignment_permissions  
          when :volunteer_profile
            admin_volunteer_profile_permissions
          when :component
            admin_component_permissions
          when :volunteer_scheduler
            permission_action.allow! if can_manage_component?
          end

          permission_action
        end

        private

        def admin_task_template_permissions
          case permission_action.action
          when :read, :create, :update, :delete, :publish, :unpublish
            permission_action.allow! if can_manage_component?
          end
        end

        def admin_task_assignment_permissions
          case permission_action.action
          when :read, :update, :bulk_approve, :bulk_reject
            permission_action.allow! if can_manage_component?
          end
        end

        def admin_volunteer_profile_permissions
          case permission_action.action
          when :read
            permission_action.allow! if can_manage_component?
          end
        end

        def admin_component_permissions
          case permission_action.action
          when :read, :update
            permission_action.allow! if can_manage_component?
          end
        end

        def can_manage_component?
          return false unless user
          return true if user.admin?
          return false unless component

          user.role_for(component.participatory_space)&.in?(%w[admin collaborator])
        end
      end
    end
  end
end
