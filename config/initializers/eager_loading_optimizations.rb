# frozen_string_literal: true

# Eager loading optimizations for Decidim queries based on performance analysis
# These optimizations address N+1 queries detected in the application

Rails.application.config.to_prepare do
  # Monkey patch for Decidim ActionLog queries to optimize eager loading
  if defined?(Decidim::ActionLog)
    Decidim::ActionLog.class_eval do
      # Scope for admin interface with optimized includes
      scope :for_admin_display, -> {
        # AVOID eager loading detected: Remove .includes([:component])
        # Component association not needed for most admin displays
        includes(:organization, :user, :participatory_space)
      }
      
      # Scope for reports that need component info
      scope :with_component_for_reports, -> {
        includes(:organization, :user, :participatory_space, :component)
      }
    end
  end
  
  # Add includes for participatory spaces when organization is accessed
  if defined?(Decidim::ParticipatoryProcess)
    Decidim::ParticipatoryProcess.class_eval do
      # USE eager loading detected: Add .includes([:organization])
      scope :with_organization, -> {
        includes(:organization)
      }
    end
  end
  
  if defined?(Decidim::Assembly)
    Decidim::Assembly.class_eval do
      # USE eager loading detected: Add .includes([:organization])
      scope :with_organization, -> {
        includes(:organization)
      }
    end
  end
  
  if defined?(Decidim::Initiative)
    Decidim::Initiative.class_eval do
      # USE eager loading detected: Add .includes([:organization])  
      scope :with_organization, -> {
        includes(:organization)
      }
    end
  end
  
  # PaperTrail Version optimizations
  if defined?(PaperTrail::Version)
    PaperTrail::Version.class_eval do
      # USE eager loading detected: Add .includes([:item])
      scope :with_item, -> {
        includes(:item)
      }
    end
  end
end