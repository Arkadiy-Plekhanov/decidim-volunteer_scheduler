# frozen_string_literal: true

module Decidim
  module VolunteerScheduler
    # Form for submitting task work with Decidim native attachments
    class TaskSubmissionForm < Decidim::Form
      include Decidim::HasUploadValidations
      include Decidim::AttachmentAttributesMethods

      mimic :task_assignment

      attribute :submission_notes, String
      attribute :hours_worked, Float
      attribute :challenges_faced, String
      attribute :add_documents, Array[Decidim::Attachment]
      attribute :documents, Array

      validates :submission_notes, presence: true, length: { minimum: 10, maximum: 5000 }
      validates :hours_worked, numericality: { greater_than: 0, less_than_or_equal_to: 100 }, allow_nil: true

      validates_upload :add_documents, uploader: Decidim::AttachmentUploader

      validate :validate_documents_count

      def map_model(model)
        self.submission_notes = model.submission_notes
        if model.submission_data.present?
          self.hours_worked = model.submission_data["hours_worked"]
          self.challenges_faced = model.submission_data["challenges_faced"]
        end
        self.documents = model.attachments.map do |attachment|
          {
            id: attachment.id,
            title: attachment.title,
            file: attachment.file
          }
        end
      end

      def documents_present?
        add_documents.present? || documents.present?
      end

      private

      def validate_documents_count
        return unless add_documents.present?

        total_docs = add_documents.size + (documents&.size || 0)
        if total_docs > 5
          errors.add(:add_documents, :too_many, count: 5)
        end
      end
    end
  end
end