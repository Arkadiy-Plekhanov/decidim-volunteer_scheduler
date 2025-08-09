# frozen_string_literal: true

module Decidim
  module VolunteerScheduler
    # Model representing a task template that volunteers can accept and complete
    class TaskTemplate < ApplicationRecord
      include Decidim::Resourceable
      include Decidim::Traceable
      include Decidim::Loggable
      
      # Organization-level architecture - templates belong to organizations
      belongs_to :organization, class_name: "Decidim::Organization"
      belongs_to :component, class_name: "Decidim::Component", optional: true

      has_many :task_assignments, dependent: :destroy, inverse_of: :task_template

      validates :title, presence: true, length: { maximum: 150 }
      validates :description, presence: true
      validates :xp_reward, presence: true, numericality: { greater_than: 0 }
      validates :level_required, presence: true, numericality: { greater_than: 0 }
      validates :category, presence: true
      validates :frequency, presence: true, inclusion: { in: %w[daily weekly monthly] }

      enum status: { draft: 0, published: 1, archived: 2 }

      scope :active, -> { published }
      scope :for_level, ->(level) { where("level_required <= ?", level) }
      scope :by_category, ->(category) { where(category: category) }
      scope :by_frequency, ->(frequency) { where(frequency: frequency) }

      def can_be_assigned_to?(volunteer_profile)
        return false unless published?
        return false if volunteer_profile.level < level_required
        return false if volunteer_profile.task_assignments.pending.where(task_template: self).exists?
        
        true
      end

      # Use counter cache for better performance
      def assignments_count
        task_assignments_count || task_assignments.size
      end

      def completed_assignments_count
        task_assignments.approved.count
      end

      def pending_assignments_count
        task_assignments.pending.count
      end

      def success_rate
        total = task_assignments_count || 0
        return 0 if total.zero?
        
        (completed_assignments_count.to_f / total * 100).round(1)
      end

      def average_completion_time
        completed = task_assignments.approved.where.not(submitted_at: nil)
        return 0 if completed.empty?
        
        total_time = completed.sum { |assignment| 
          (assignment.submitted_at - assignment.assigned_at).to_i
        }
        
        (total_time / completed.count / 1.day).round(1)
      end
    end
  end
end
