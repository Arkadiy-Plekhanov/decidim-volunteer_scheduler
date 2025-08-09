# frozen_string_literal: true

class CreateDecidimVolunteerSchedulerTaskTemplates < ActiveRecord::Migration[6.1]
  def change
    create_table :decidim_volunteer_scheduler_task_templates do |t|
      t.references :component, null: false, foreign_key: { to_table: :decidim_components }, index: { name: 'idx_task_templates_component' }
      
      t.string :title, null: false, limit: 150
      t.text :description, null: false
      t.integer :xp_reward, null: false, default: 20
      t.integer :level_required, null: false, default: 1
      t.string :category, null: false
      t.string :frequency, null: false, default: 'daily'
      t.integer :status, null: false, default: 0
      
      t.timestamps null: false
      
      t.index [:component_id, :status], name: 'idx_task_templates_component_status'
      t.index [:level_required, :status], name: 'idx_task_templates_level_status'
      t.index [:category, :status], name: 'idx_task_templates_category_status'
    end
  end
end
