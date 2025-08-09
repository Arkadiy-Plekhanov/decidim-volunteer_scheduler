# frozen_string_literal: true

module Decidim
  module VolunteerScheduler
    # A form object used to create task assignments from the public interface.
    class TaskAssignmentForm < Decidim::Form
      include Decidim::HasUploadValidations

      attribute :task_template_id, Integer
      attribute :accept_terms, Boolean

      validates :task_template_id, presence: true
      validates :accept_terms, acceptance: true

      validate :task_template_exists
      validate :volunteer_profile_exists

      def task_template
        @task_template ||= TaskTemplate.find_by(
          id: task_template_id,
          organization: current_organization
        )
      end

      def volunteer_profile
        @volunteer_profile ||= current_user&.volunteer_profile
      end

      private

      def task_template_exists
        errors.add(:task_template_id, :invalid) unless task_template
      end

      def volunteer_profile_exists
        errors.add(:base, :no_profile) unless volunteer_profile
      end
    end
  end
end