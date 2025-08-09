# frozen_string_literal: true

module Decidim
  module VolunteerScheduler
    # Serializes a TaskAssignment for data export
    class TaskAssignmentSerializer < Decidim::Exporters::Serializer
      include Decidim::ApplicationHelper
      include Decidim::ResourceHelper
      include Decidim::TranslationsHelper

      # Public: Initializes the serializer with a task assignment.
      def initialize(task_assignment)
        @task_assignment = task_assignment
      end

      # Public: Exports a hash with the serialized data for this task assignment.
      def serialize
        {
          id: task_assignment.id,
          task_title: translated_attribute(task_assignment.task_template.title),
          task_description: translated_attribute(task_assignment.task_template.description),
          volunteer_name: task_assignment.assignee.user.name,
          volunteer_email: task_assignment.assignee.user.email,
          volunteer_level: task_assignment.assignee.level,
          status: task_assignment.status,
          assigned_at: task_assignment.assigned_at,
          due_date: task_assignment.due_date,
          submitted_at: task_assignment.submitted_at,
          reviewed_at: task_assignment.reviewed_at,
          reviewer_name: task_assignment.reviewer&.name,
          submission_notes: task_assignment.submission_notes,
          admin_notes: task_assignment.admin_notes,
          xp_reward: task_assignment.task_template.xp_reward,
          scicent_reward: task_assignment.task_template.scicent_reward,
          hours_worked: submission_data["hours_worked"],
          challenges_faced: submission_data["challenges_faced"],
          category: task_assignment.task_template.category,
          frequency: task_assignment.task_template.frequency,
          created_at: task_assignment.created_at,
          updated_at: task_assignment.updated_at
        }
      end

      private

      attr_reader :task_assignment

      def submission_data
        task_assignment.submission_data || {}
      end
    end
  end
end