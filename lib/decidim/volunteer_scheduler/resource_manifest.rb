# frozen_string_literal: true

module Decidim
  module VolunteerScheduler
    # Defines the resource manifest for the volunteer scheduler component
    class ResourceManifest
      def self.register_resources
        Decidim.register_resource(:task_template) do |resource|
          resource.model_class_name = "Decidim::VolunteerScheduler::TaskTemplate"
          resource.card = "decidim/volunteer_scheduler/task_template_card"
          resource.actions = %w[create update destroy publish unpublish]
          resource.searchable = true
        end

        Decidim.register_resource(:task_assignment) do |resource|
          resource.model_class_name = "Decidim::VolunteerScheduler::TaskAssignment"
          resource.actions = %w[create update approve reject submit]
          resource.searchable = false
        end

        Decidim.register_resource(:volunteer_profile) do |resource|
          resource.model_class_name = "Decidim::VolunteerScheduler::VolunteerProfile"
          resource.actions = %w[create update]
          resource.searchable = true
        end
      end

      def self.register_stats
        Decidim.register_stat :volunteers_count, 
                             priority: Decidim::StatsRegistry::HIGH_PRIORITY,
                             tag: :volunteers

        Decidim.register_stat :tasks_completed_count, 
                             priority: Decidim::StatsRegistry::MEDIUM_PRIORITY,
                             tag: :tasks

        Decidim.register_stat :total_xp_awarded, 
                             priority: Decidim::StatsRegistry::LOW_PRIORITY,
                             tag: :gamification
      end

      def self.register_metrics
        Decidim.metrics_registry.register(
          :volunteer_registrations,
          "Decidim::VolunteerScheduler::Metrics::VolunteerRegistrationsMetric"
        )

        Decidim.metrics_registry.register(
          :task_completions,
          "Decidim::VolunteerScheduler::Metrics::TaskCompletionsMetric"
        )

        Decidim.metrics_registry.register(
          :referral_chains,
          "Decidim::VolunteerScheduler::Metrics::ReferralChainsMetric"
        )
      end
    end
  end
end