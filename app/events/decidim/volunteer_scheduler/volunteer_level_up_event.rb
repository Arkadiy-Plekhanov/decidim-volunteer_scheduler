# frozen_string_literal: true

module Decidim
  module VolunteerScheduler
    # Event triggered when a volunteer levels up
    class VolunteerLevelUpEvent < Decidim::Events::SimpleEvent
      def event_has_roles?
        false
      end

      def old_level
        extra[:old_level]
      end

      def new_level
        extra[:new_level]
      end

      def capabilities_unlocked
        VolunteerProfile::LEVEL_CAPABILITIES[new_level] - VolunteerProfile::LEVEL_CAPABILITIES[old_level]
      end

      def notification_title
        I18n.t(
          "events.volunteer_level_up.notification_title",
          new_level: new_level,
          scope: "decidim.volunteer_scheduler"
        )
      end

      def email_subject
        I18n.t(
          "events.volunteer_level_up.email_subject",
          new_level: new_level,
          scope: "decidim.volunteer_scheduler"
        )
      end

      def email_intro
        I18n.t(
          "events.volunteer_level_up.email_intro",
          old_level: old_level,
          new_level: new_level,
          scope: "decidim.volunteer_scheduler"
        )
      end

      def email_outro
        if capabilities_unlocked.any?
          I18n.t(
            "events.volunteer_level_up.email_outro_with_capabilities",
            capabilities: capabilities_unlocked.join(", "),
            scope: "decidim.volunteer_scheduler"
          )
        else
          I18n.t(
            "events.volunteer_level_up.email_outro",
            scope: "decidim.volunteer_scheduler"
          )
        end
      end

      def resource_path
        Decidim::EngineRouter.main_proxy(resource.component).root_path
      end
    end
  end
end