# frozen_string_literal: true

module Decidim
  module VolunteerScheduler
    # Event triggered when a task assignment is approved
    class TaskApprovedEvent < Decidim::Events::SimpleEvent
      def event_has_roles?
        false
      end

      def resource_title
        translated_attribute(resource.task_template.title)
      end

      def resource_text
        translated_attribute(resource.task_template.description)
      end

      def resource_path
        Decidim::EngineRouter.main_proxy(resource.task_template.component).task_assignment_path(resource)
      end

      def xp_earned
        resource.task_template.xp_reward
      end

      def notification_title
        I18n.t(
          "events.task_approved.notification_title",
          resource_title: resource_title,
          xp_earned: xp_earned,
          scope: "decidim.volunteer_scheduler"
        )
      end

      def email_subject
        I18n.t(
          "events.task_approved.email_subject",
          resource_title: resource_title,
          scope: "decidim.volunteer_scheduler"
        )
      end

      def email_intro
        I18n.t(
          "events.task_approved.email_intro",
          resource_title: resource_title,
          xp_earned: xp_earned,
          scope: "decidim.volunteer_scheduler"
        )
      end

      def email_outro
        I18n.t(
          "events.task_approved.email_outro",
          scope: "decidim.volunteer_scheduler"
        )
      end
    end
  end
end