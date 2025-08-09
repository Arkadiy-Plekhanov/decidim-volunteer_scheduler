# frozen_string_literal: true

class MakeVolunteerProfilesOrganizationLevel < ActiveRecord::Migration[6.1]
  def change
    # Make component_id nullable for organization-level volunteer profiles
    change_column_null :decidim_volunteer_scheduler_volunteer_profiles, :component_id, true
    
    # Add comment to clarify the new architecture
    change_column_comment :decidim_volunteer_scheduler_volunteer_profiles, :component_id, 
                         "Optional - for campaign-specific volunteer tracking"
    
    # Update existing profiles to be organization-level
    reversible do |dir|
      dir.up do
        # Set component_id to null for existing profiles to make them organization-level
        execute <<-SQL
          UPDATE decidim_volunteer_scheduler_volunteer_profiles
          SET component_id = NULL
          WHERE component_id IS NOT NULL;
        SQL
      end
      
      # Note: No down migration since we're simplifying the architecture
    end
    
    # Add constraint that organization_id is always required
    add_check_constraint :decidim_volunteer_scheduler_volunteer_profiles,
                        "organization_id IS NOT NULL",
                        name: "volunteer_profile_organization_required"
  end
end