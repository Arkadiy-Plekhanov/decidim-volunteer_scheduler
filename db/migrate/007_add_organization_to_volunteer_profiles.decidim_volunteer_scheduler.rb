# frozen_string_literal: true

class AddOrganizationToVolunteerProfiles < ActiveRecord::Migration[6.1]
  def change
    add_reference :decidim_volunteer_scheduler_volunteer_profiles, 
                  :organization, 
                  null: false, 
                  foreign_key: { to_table: :decidim_organizations }, 
                  index: { name: 'idx_volunteer_profiles_organization' }
    
    # Populate organization_id for existing records
    reversible do |dir|
      dir.up do
        execute <<-SQL
          UPDATE decidim_volunteer_scheduler_volunteer_profiles 
          SET organization_id = (
            SELECT decidim_organizations.id 
            FROM decidim_components 
            JOIN decidim_participatory_processes ON decidim_components.decidim_participatory_space_id = decidim_participatory_processes.id 
                AND decidim_components.decidim_participatory_space_type = 'Decidim::ParticipatoryProcess'
            JOIN decidim_organizations ON decidim_participatory_processes.decidim_organization_id = decidim_organizations.id
            WHERE decidim_components.id = decidim_volunteer_scheduler_volunteer_profiles.component_id
          );
        SQL
        
        execute <<-SQL
          UPDATE decidim_volunteer_scheduler_volunteer_profiles 
          SET organization_id = (
            SELECT decidim_organizations.id 
            FROM decidim_components 
            JOIN decidim_assemblies ON decidim_components.decidim_participatory_space_id = decidim_assemblies.id 
                AND decidim_components.decidim_participatory_space_type = 'Decidim::Assembly'
            JOIN decidim_organizations ON decidim_assemblies.decidim_organization_id = decidim_organizations.id
            WHERE decidim_components.id = decidim_volunteer_scheduler_volunteer_profiles.component_id
          )
          WHERE organization_id IS NULL;
        SQL
      end
    end
  end
end