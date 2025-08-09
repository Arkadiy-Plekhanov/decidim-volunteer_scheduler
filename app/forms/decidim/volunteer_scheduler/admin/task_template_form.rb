# frozen_string_literal: true

module Decidim
  module VolunteerScheduler
    module Admin
      # A form object used to create and update task templates in the admin panel
      class TaskTemplateForm < Decidim::Form
        include Decidim::TranslatableAttributes
        include Decidim::HasCategory
        include Decidim::HasUploadValidations

        translatable_attribute :title, String
        translatable_attribute :description, String
        
        attribute :xp_reward, Integer
        attribute :scicent_reward, Float
        attribute :level_required, Integer
        attribute :category, String
        attribute :frequency, String
        attribute :status, String
        attribute :max_assignments_per_day, Integer
        attribute :deadline_days, Integer
        attribute :instructions, String
        attribute :skills_required, Array[String]
        attribute :deleted_attachment_ids, Array[Integer]

        validates :title, translatable_presence: true
        validates :description, translatable_presence: true
        validates :xp_reward, presence: true, numericality: { greater_than: 0, less_than_or_equal_to: 1000 }
        validates :level_required, presence: true, inclusion: { in: 1..3 }
        validates :category, presence: true, inclusion: { 
          in: %w[outreach technical administrative content_creation training mentoring] 
        }
        validates :frequency, presence: true, inclusion: { 
          in: %w[one_time daily weekly monthly] 
        }
        validates :deadline_days, presence: true, numericality: { greater_than: 0, less_than_or_equal_to: 30 }
        validates :max_assignments_per_day, numericality: { greater_than: 0, less_than_or_equal_to: 100 }, allow_blank: true

        validate :validate_skills_format

        def map_model(model)
          super
          self.skills_required = model.metadata["skills_required"] if model.metadata
        end

        def skills_required
          @skills_required || []
        end

        def category_options
          [
            ["Outreach & Community Building", "outreach"],
            ["Technical & Development", "technical"],
            ["Administrative & Operations", "administrative"],
            ["Content Creation", "content_creation"],
            ["Training & Education", "training"],
            ["Mentoring & Support", "mentoring"]
          ]
        end

        def frequency_options
          [
            ["One Time", "one_time"],
            ["Daily", "daily"],
            ["Weekly", "weekly"],
            ["Monthly", "monthly"]
          ]
        end

        def level_options
          [
            ["Level 1 - Beginner (0-99 XP)", 1],
            ["Level 2 - Intermediate (100-499 XP)", 2],
            ["Level 3 - Advanced (500+ XP)", 3]
          ]
        end

        private

        def validate_skills_format
          return if skills_required.blank?
          
          unless skills_required.is_a?(Array)
            errors.add(:skills_required, :invalid_format)
            return
          end

          skills_required.each do |skill|
            unless skill.is_a?(String) && skill.length <= 50
              errors.add(:skills_required, :invalid_skill)
            end
          end
        end
      end
    end
  end
end