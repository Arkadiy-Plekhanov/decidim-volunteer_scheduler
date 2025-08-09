# frozen_string_literal: true

module Decidim
  module VolunteerScheduler
    # Event triggered when a task is submitted for review
    class TaskSubmittedEvent < Decidim::Events::SimpleEvent
      def event_has_roles?
        true
      end

      def role_permissions
        {
          valuator: :review,
          admin: :review
        }
      end

      def resource_title
        translated_attribute(resource.task_template.title)
      end

      def volunteer_name
        resource.assignee.user.name
      end

      def volunteer_level
        resource.assignee.level
      end

      def notification_title
        I18n.t(
          "events.task_submitted.notification_title",
          resource_title: resource_title,
          volunteer_name: volunteer_name,
          scope: "decidim.volunteer_scheduler"
        )
      end

      def email_subject
        I18n.t(
          "events.task_submitted.email_subject",
          resource_title: resource_title,
          scope: "decidim.volunteer_scheduler"
        )
      end

      def email_intro
        I18n.t(
          "events.task_submitted.email_intro",
          volunteer_name: volunteer_name,
          volunteer_level: volunteer_level,
          resource_title: resource_title,
          scope: "decidim.volunteer_scheduler"
        )
      end

      def email_outro
        I18n.t(
          "events.task_submitted.email_outro",
          scope: "decidim.volunteer_scheduler"
        )
      end

      def resource_path
        Decidim::EngineRouter.admin_proxy(resource.task_template.component).task_assignment_path(resource)
      end
    end
  end
end