# frozen_string_literal: true

module Decidim
  module VolunteerScheduler
    # GraphQL type for VolunteerProfile
    class VolunteerProfileType < Decidim::Api::Types::BaseObject
      implements Decidim::Core::TimestampsInterface
      
      description "A volunteer profile in the system"
      
      field :id, GraphQL::Types::ID, 
            null: false,
            description: "The internal ID of this volunteer profile"
            
      field :user, Decidim::Core::UserType, 
            null: false,
            description: "The user associated with this profile"
            
      field :level, GraphQL::Types::Int, 
            null: false,
            description: "Current level of the volunteer (1-3)"
            
      field :total_xp, GraphQL::Types::Int, 
            null: false,
            description: "Total XP accumulated by the volunteer"
            
      field :referral_code, GraphQL::Types::String, 
            null: false,
            description: "Unique referral code for this volunteer"
            
      field :activity_multiplier, GraphQL::Types::Float, 
            null: false,
            description: "Current activity multiplier affecting XP rewards"
            
      field :tasks_completed_count, GraphQL::Types::Int, 
            null: false,
            description: "Number of tasks completed by this volunteer" do
        def resolve
          object.task_assignments.approved.count
        end
      end
      
      field :tasks_in_progress_count, GraphQL::Types::Int, 
            null: false,
            description: "Number of tasks currently in progress" do
        def resolve
          object.task_assignments.where(status: [:pending, :submitted]).count
        end
      end
      
      field :referrals_count, GraphQL::Types::Int, 
            null: false,
            description: "Number of successful referrals made" do
        def resolve
          object.referrals_made.active.count
        end
      end
      
      field :can_accept_level_2_tasks, GraphQL::Types::Boolean, 
            null: false,
            description: "Whether volunteer can accept level 2 tasks" do
        def resolve
          object.level >= 2
        end
      end
      
      field :can_accept_level_3_tasks, GraphQL::Types::Boolean, 
            null: false,
            description: "Whether volunteer can accept level 3 tasks" do
        def resolve
          object.level >= 3
        end
      end
      
      field :next_level_xp_requirement, GraphQL::Types::Int, 
            null: true,
            description: "XP required to reach next level" do
        def resolve
          case object.level
          when 1 then 100
          when 2 then 500
          else nil
          end
        end
      end
      
      field :xp_to_next_level, GraphQL::Types::Int, 
            null: true,
            description: "Remaining XP needed for next level" do
        def resolve
          requirement = context[:next_level_xp_requirement]
          requirement ? [requirement - object.total_xp, 0].max : nil
        end
      end
    end
  end
end