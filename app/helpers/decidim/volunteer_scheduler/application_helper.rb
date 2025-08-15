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

      def assignment_status_color(assignment)
        case assignment.status.to_s
        when "pending"
          "bg-yellow-100 text-yellow-800"
        when "in_progress"
          "bg-blue-100 text-blue-800"
        when "submitted"
          "bg-purple-100 text-purple-800"
        when "approved", "completed"
          "bg-green-100 text-green-800"
        when "rejected"
          "bg-red-100 text-red-800"
        else
          "bg-gray-100 text-gray-800"
        end
      end

      def assignment_status_icon(assignment)
        case assignment.status.to_s
        when "pending"
          "time-line"
        when "in_progress"
          "loader-3-line"
        when "submitted"
          "mail-send-line"
        when "approved", "completed"
          "check-line"
        when "rejected"
          "close-line"
        else
          "question-line"
        end
      end
    end
  end
end
