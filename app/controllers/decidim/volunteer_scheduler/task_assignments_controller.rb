# frozen_string_literal: true

module Decidim
  module VolunteerScheduler
    # Controller for managing task assignments
    class TaskAssignmentsController < ApplicationController
      before_action :set_task_assignment, only: [:show, :update]
      before_action :set_task_template, only: [:create, :accept]

      def index
        enforce_permission_to :read, :task_assignment
        
        @task_assignments = current_volunteer_profile.task_assignments
                                                   .includes(:task_template)
                                                   .order(assigned_at: :desc)
                                                   .page(params[:page])
      end

      def show
        enforce_permission_to :read, :task_assignment, task_assignment: @task_assignment
      end

      def create
        # Proper authorization for gem distribution
        enforce_permission_to :create, :task_assignment
        
        return redirect_with_error("No volunteer profile found") unless current_volunteer_profile
        return redirect_with_error("No task template found") unless @task_template
        return redirect_with_error unless can_assign_task?
        
        @task_assignment = TaskAssignment.new(
          task_template: @task_template,
          assignee: current_volunteer_profile,
          status: :pending,
          assigned_at: Time.current,
          due_date: calculate_due_date
        )
        
        if @task_assignment.save
          redirect_to task_assignment_path(@task_assignment),
                     notice: I18n.t("decidim.volunteer_scheduler.task_assignments.create.success")
        else
          redirect_with_error(@task_assignment.errors.full_messages.first)
        end
      end
      
      # Accept a task (alias for create with better naming)
      def accept
        create
      end

      def update
        enforce_permission_to :update, :task_assignment, task_assignment: @task_assignment
        
        case params[:action_type]
        when "submit"
          submit_assignment
        else
          redirect_with_error("Invalid action")
        end
      end

      private

      def set_task_assignment
        @task_assignment = TaskAssignment.find(params[:id])
      end

      def set_task_template
        # Handle both member route (:id) and nested route (:task_template_id)
        template_id = params[:id] || params[:task_template_id]
        @task_template = TaskTemplate.find(template_id)
      end

      def can_assign_task?
        # Check level requirements
        return false if @task_template.level_required > current_volunteer_profile.level
        
        # Check if already has pending assignment for this template
        return false if current_volunteer_profile.task_assignments
                                                 .pending
                                                 .where(task_template: @task_template)
                                                 .exists?
        
        # Check daily task limit
        today_count = current_volunteer_profile.task_assignments
                                              .where("assigned_at >= ?", Time.current.beginning_of_day)
                                              .count
        max_daily = 5  # Default for organization-level tasks
        return false if today_count >= max_daily
        
        true
      end
      
      def calculate_due_date
        deadline_days = 7  # Default for organization-level tasks
        deadline_days.days.from_now
      end

      def submit_assignment
        if @task_assignment.submit_work!(params[:submission_notes])
          redirect_to task_assignment_path(@task_assignment),
                     notice: "Task submitted successfully!"
        else
          redirect_with_error("Failed to submit assignment")
        end
      end

      def redirect_with_error(message = nil)
        message ||= "An error occurred"
        redirect_to root_path, alert: message
      end
    end
  end
end
