# frozen_string_literal: true

module Decidim
  module VolunteerScheduler
    # Form for submitting task work through the follow-up system
    class TaskSubmissionForm < Decidim::Form
      include Decidim::HasUploadValidations

      mimic :task_submission

      attribute :report, String
      attribute :hours_worked, Float
      attribute :challenges_faced, String
      attribute :attachments, Array[Integer]
      attribute :additional_notes, String

      validates :report, presence: true, length: { minimum: 10, maximum: 5000 }
      validates :hours_worked, presence: true, numericality: { greater_than: 0, less_than_or_equal_to: 100 }
      
      validate :validate_attachments

      def map_model(model)
        self.report = model.submission_notes
        if model.submission_data.present?
          self.hours_worked = model.submission_data["hours_worked"]
          self.challenges_faced = model.submission_data["challenges_faced"]
          self.attachments = model.submission_data["attachments"]
        end
      end

      def attachment_ids
        attachments&.reject(&:blank?)&.map(&:to_i) || []
      end

      private

      def validate_attachments
        return unless attachments.present?
        
        if attachments.size > 5
          errors.add(:attachments, :too_many, count: 5)
        end
      end
    end
  end
end