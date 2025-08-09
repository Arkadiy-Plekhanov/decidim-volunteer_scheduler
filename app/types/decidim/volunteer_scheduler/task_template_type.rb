# frozen_string_literal: true

module Decidim
  module VolunteerScheduler
    # GraphQL type for TaskTemplate
    class TaskTemplateType < Decidim::Api::Types::BaseObject
      implements Decidim::Core::TimestampsInterface
      
      description "A task template that defines volunteer activities"
      
      field :id, GraphQL::Types::ID, 
            null: false,
            description: "The internal ID of this task template"
            
      field :title, Decidim::Core::TranslatedFieldType, 
            null: false,
            description: "The title of this task template"
            
      field :description, Decidim::Core::TranslatedFieldType, 
            null: true,
            description: "The description of this task template"
            
      field :xp_reward, GraphQL::Types::Int, 
            null: false,
            description: "XP points awarded for completing this task"
            
      field :scicent_reward, GraphQL::Types::Float, 
            null: true,
            description: "Scicent tokens awarded for completing this task"
            
      field :level_required, GraphQL::Types::Int, 
            null: false,
            description: "Minimum volunteer level required to accept this task"
            
      field :category, GraphQL::Types::String, 
            null: false,
            description: "Task category (outreach, technical, administrative, etc.)"
            
      field :frequency, GraphQL::Types::String, 
            null: false,
            description: "Task frequency (one_time, daily, weekly, monthly)"
            
      field :status, GraphQL::Types::String, 
            null: false,
            description: "Current status (draft, published, archived)"
            
      field :deadline_days, GraphQL::Types::Int, 
            null: false,
            description: "Number of days volunteers have to complete the task"
            
      field :max_assignments_per_day, GraphQL::Types::Int, 
            null: true,
            description: "Maximum number of volunteers who can accept this task per day"
            
      field :instructions, GraphQL::Types::String, 
            null: true,
            description: "Detailed instructions for completing the task"
            
      field :is_available, GraphQL::Types::Boolean, 
            null: false,
            description: "Whether this task is currently available for volunteers" do
        def resolve
          object.status == "published"
        end
      end
      
      field :assignments_count, GraphQL::Types::Int, 
            null: false,
            description: "Total number of assignments created from this template" do
        def resolve
          object.task_assignments.count
        end
      end
      
      field :completions_count, GraphQL::Types::Int, 
            null: false,
            description: "Number of successful completions" do
        def resolve
          object.task_assignments.approved.count
        end
      end
      
      field :available_slots_today, GraphQL::Types::Int, 
            null: true,
            description: "Remaining slots available for today" do
        def resolve
          return nil unless object.max_assignments_per_day
          
          today_count = object.task_assignments
                             .where("assigned_at >= ?", Time.current.beginning_of_day)
                             .count
          
          [object.max_assignments_per_day - today_count, 0].max
        end
      end
      
      field :skills_required, [GraphQL::Types::String], 
            null: true,
            description: "List of skills required for this task" do
        def resolve
          object.metadata&.dig("skills_required") || []
        end
      end
    end
  end
end