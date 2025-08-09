# frozen_string_literal: true

module Decidim
  module VolunteerScheduler
    # Custom helpers, scoped to the volunteer_scheduler engine.
    #
    module ApplicationHelper
      # Public-facing helper methods for volunteer scheduler
      
      def assignment_status_class(assignment)
        case assignment.status.to_s
        when "pending"
          "warning"
        when "submitted"
          "primary"
        when "approved", "completed"
          "success"
        when "rejected"
          "alert"
        else
          "secondary"
        end
      end
      
      def referral_url(volunteer_profile)
        # Use Decidim's organization-aware URL generation pattern from layout_helper
        decidim.root_url(host: current_organization.host, ref: volunteer_profile.referral_code)
      end
      
      def xp_progress_percentage(volunteer_profile)
        volunteer_profile.level_progress_percentage
      end
      
      def days_until_due(assignment)
        return nil unless assignment.due_date
        days = assignment.days_until_due
        
        if days < 0
          content_tag(:span, t("decidim.volunteer_scheduler.task_assignments.overdue"), class: "label alert")
        elsif days == 0
          content_tag(:span, t("decidim.volunteer_scheduler.task_assignments.due_today"), class: "label warning")
        elsif days == 1
          content_tag(:span, t("decidim.volunteer_scheduler.task_assignments.due_tomorrow"), class: "label warning")
        else
          t("decidim.volunteer_scheduler.task_assignments.due_in_days", days: days)
        end
      end
    end
  end
end
