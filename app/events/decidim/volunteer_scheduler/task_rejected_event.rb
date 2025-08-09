# frozen_string_literal: true

module Decidim
  module VolunteerScheduler
    # Event triggered when a task assignment is rejected
    class TaskRejectedEvent < Decidim::Events::SimpleEvent
      def event_has_roles?
        false
      end

      def resource_title
        translated_attribute(resource.task_template.title)
      end

      def resource_path
        Decidim::EngineRouter.main_proxy(resource.task_template.component).task_assignment_path(resource)
      end

      def rejection_reason
        resource.review_notes
      end

      def notification_title
        I18n.t(
          "events.task_rejected.notification_title",
          resource_title: resource_title,
          scope: "decidim.volunteer_scheduler"
        )
      end

      def email_subject
        I18n.t(
          "events.task_rejected.email_subject",
          resource_title: resource_title,
          scope: "decidim.volunteer_scheduler"
        )
      end

      def email_intro
        I18n.t(
          "events.task_rejected.email_intro",
          resource_title: resource_title,
          rejection_reason: rejection_reason,
          scope: "decidim.volunteer_scheduler"
        )
      end

      def email_outro
        I18n.t(
          "events.task_rejected.email_outro",
          scope: "decidim.volunteer_scheduler"
        )
      end
    end
  end
end