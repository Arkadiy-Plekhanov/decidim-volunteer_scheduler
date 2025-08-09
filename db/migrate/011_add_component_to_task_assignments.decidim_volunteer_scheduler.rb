# frozen_string_literal: true

class AddComponentToTaskAssignments < ActiveRecord::Migration[6.1]
  def change
    add_reference :decidim_volunteer_scheduler_task_assignments, 
                  :decidim_component, 
                  foreign_key: true,
                  index: true,
                  null: true
  end
end