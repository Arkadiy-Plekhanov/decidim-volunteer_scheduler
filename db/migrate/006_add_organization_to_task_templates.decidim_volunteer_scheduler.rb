# frozen_string_literal: true

class AddOrganizationToTaskTemplates < ActiveRecord::Migration[6.1]
  def change
    add_reference :decidim_volunteer_scheduler_task_templates, 
                  :organization, 
                  null: false, 
                  foreign_key: { to_table: :decidim_organizations }, 
                  index: { name: 'idx_task_templates_organization' }
    
    # Make component_id nullable for organization-level templates
    change_column_null :decidim_volunteer_scheduler_task_templates, :component_id, true
    
    # Populate organization_id for existing records
    reversible do |dir|
      dir.up do
        execute <<-SQL
          UPDATE decidim_volunteer_scheduler_task_templates 
          SET organization_id = (
            SELECT decidim_organizations.id 
            FROM decidim_components 
            JOIN decidim_participatory_processes ON decidim_components.decidim_participatory_space_id = decidim_participatory_processes.id 
                AND decidim_components.decidim_participatory_space_type = 'Decidim::ParticipatoryProcess'
            JOIN decidim_organizations ON decidim_participatory_processes.decidim_organization_id = decidim_organizations.id
            WHERE decidim_components.id = decidim_volunteer_scheduler_task_templates.component_id
          )
          WHERE component_id IS NOT NULL;
        SQL
        
        execute <<-SQL
          UPDATE decidim_volunteer_scheduler_task_templates 
          SET organization_id = (
            SELECT decidim_organizations.id 
            FROM decidim_components 
            JOIN decidim_assemblies ON decidim_components.decidim_participatory_space_id = decidim_assemblies.id 
                AND decidim_components.decidim_participatory_space_type = 'Decidim::Assembly'
            JOIN decidim_organizations ON decidim_assemblies.decidim_organization_id = decidim_organizations.id
            WHERE decidim_components.id = decidim_volunteer_scheduler_task_templates.component_id
          )
          WHERE component_id IS NOT NULL AND organization_id IS NULL;
        SQL
      end
    end
    
    # No need for constraint since organization_id is required (null: false)
  end
end