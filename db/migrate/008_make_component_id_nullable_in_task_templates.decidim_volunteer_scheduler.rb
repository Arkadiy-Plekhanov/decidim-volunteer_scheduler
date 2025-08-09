# frozen_string_literal: true

class MakeComponentIdNullableInTaskTemplates < ActiveRecord::Migration[6.1]
  def change
    # Make component_id nullable for organization-level task templates
    change_column_null :decidim_volunteer_scheduler_task_templates, :component_id, true
    
    # Add comment to clarify the new architecture
    change_column_comment :decidim_volunteer_scheduler_task_templates, :component_id, 
                         "Optional - null for organization-level templates"
    
    # Add check constraint to ensure either component_id or organization_id is present
    # (organization_id should always be present, but this adds extra safety)
    reversible do |dir|
      dir.up do
        execute <<-SQL
          ALTER TABLE decidim_volunteer_scheduler_task_templates
          ADD CONSTRAINT task_template_scope_check 
          CHECK (organization_id IS NOT NULL);
        SQL
      end
      
      dir.down do
        execute <<-SQL
          ALTER TABLE decidim_volunteer_scheduler_task_templates
          DROP CONSTRAINT IF EXISTS task_template_scope_check;
        SQL
      end
    end
  end
end