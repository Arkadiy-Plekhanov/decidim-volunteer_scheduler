# frozen_string_literal: true

class CreateDecidimVolunteerSchedulerTaskAssignments < ActiveRecord::Migration[6.1]
  def change
    create_table :decidim_volunteer_scheduler_task_assignments do |t|
      t.references :task_template, null: false, foreign_key: { to_table: :decidim_volunteer_scheduler_task_templates }, index: { name: 'idx_task_assignments_template' }
      t.references :assignee, null: false, foreign_key: { to_table: :decidim_volunteer_scheduler_volunteer_profiles }, index: { name: 'idx_task_assignments_assignee' }
      t.references :reviewer, null: true, foreign_key: { to_table: :decidim_users }, index: { name: 'idx_task_assignments_reviewer' }
      
      t.integer :status, null: false, default: 0
      t.datetime :assigned_at, null: false
      t.datetime :due_date
      t.datetime :submitted_at
      t.datetime :reviewed_at
      
      t.text :submission_notes
      t.text :review_notes
      
      t.timestamps null: false
      
      t.index [:assignee_id, :status], name: 'idx_task_assignments_assignee_status'
      t.index [:task_template_id, :status], name: 'idx_task_assignments_template_status'
      t.index [:status, :submitted_at], name: 'idx_task_assignments_status_submitted'
      t.index [:due_date, :status], name: 'idx_task_assignments_due_status'
    end
  end
end
