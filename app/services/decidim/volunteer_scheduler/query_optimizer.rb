# frozen_string_literal: true

module Decidim
  module VolunteerScheduler
    # Service to optimize common queries and reduce N+1 queries
    class QueryOptimizer
      class << self
        # Optimize ActionLog queries for admin interface
        def optimize_action_logs(scope = Decidim::ActionLog.all)
          # AVOID eager loading detected: Remove .includes([:component])
          # ADD required includes for organization, user, participatory_space
          scope.includes(:organization, :user, :participatory_space)
        end

        # Optimize participatory process queries
        def optimize_participatory_processes(scope = Decidim::ParticipatoryProcess.all)
          # USE eager loading detected: Add .includes([:organization])
          scope.includes(:organization)
        end

        # Optimize assembly queries  
        def optimize_assemblies(scope = Decidim::Assembly.all)
          # USE eager loading detected: Add .includes([:organization])
          scope.includes(:organization)
        end

        # Optimize initiative queries
        def optimize_initiatives(scope = Decidim::Initiative.all)
          # USE eager loading detected: Add .includes([:organization])
          scope.includes(:organization) if defined?(Decidim::Initiative)
        end

        # Optimize PaperTrail version queries
        def optimize_versions(scope = PaperTrail::Version.all)
          # USE eager loading detected: Add .includes([:item])
          scope.includes(:item)
        end
        
        # General optimization for volunteer scheduler models
        def optimize_task_assignments_with_templates(scope = TaskAssignment.all)
          scope.includes(:task_template, assignee: :user)
        end
        
        def optimize_task_templates_without_assignments(scope = TaskTemplate.all)
          # Use counter cache instead of includes for task_assignments
          scope
        end
        
        def optimize_volunteer_profiles_with_user(scope = VolunteerProfile.all)
          scope.includes(:user, :organization)
        end
      end
    end
  end
end