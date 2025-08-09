# frozen_string_literal: true

class AddSubmissionDataToTaskAssignments < ActiveRecord::Migration[6.1]
  def change
    add_column :decidim_volunteer_scheduler_task_assignments, :submission_data, :jsonb, default: {}
    add_index :decidim_volunteer_scheduler_task_assignments, :submission_data, using: :gin
  end
end