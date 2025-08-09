# frozen_string_literal: true

class AddTaskAssignmentsCountToTaskTemplates < ActiveRecord::Migration[6.1]
  def up
    add_column :decidim_volunteer_scheduler_task_templates, :task_assignments_count, :integer, default: 0, null: false
    
    # Reset counter cache for existing records after column is added
    Decidim::VolunteerScheduler::TaskTemplate.find_each do |template|
      Decidim::VolunteerScheduler::TaskTemplate.reset_counters(template.id, :task_assignments)
    end
  end
  
  def down
    remove_column :decidim_volunteer_scheduler_task_templates, :task_assignments_count
  end
end