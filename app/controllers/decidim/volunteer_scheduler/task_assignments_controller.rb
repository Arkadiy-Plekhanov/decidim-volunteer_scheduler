# frozen_string_literal: true

module Decidim
  module VolunteerScheduler
    # Controller for managing task assignments
    class TaskAssignmentsController < ApplicationController
      before_action :set_task_assignment, only: [:show, :update, :submit]
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

        unless current_volunteer_profile
          return redirect_with_error(t("decidim.volunteer_scheduler.task_assignments.create.no_profile"))
        end

        unless @task_template
          return redirect_with_error(t("decidim.volunteer_scheduler.task_assignments.create.no_template"))
        end

        # Check assignment eligibility with specific error messages
        error_message = check_assignment_eligibility
        return redirect_with_error(error_message) if error_message

        @task_assignment = TaskAssignment.new(
          task_template: @task_template,
          assignee: current_volunteer_profile,
          status: :pending,
          assigned_at: Time.current,
          due_date: calculate_due_date
        )

        if @task_assignment.save
          redirect_to task_assignment_path(@task_assignment),
                     notice: t("decidim.volunteer_scheduler.task_assignments.create.success")
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

      # Public action for submitting task work
      def submit
        enforce_permission_to :update, :task_assignment, task_assignment: @task_assignment
        submit_assignment
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

      def check_assignment_eligibility
        # Check level requirements
        if @task_template.level_required > current_volunteer_profile.level
          return t("decidim.volunteer_scheduler.task_assignments.create.insufficient_level",
                  required: @task_template.level_required,
                  current: current_volunteer_profile.level)
        end

        # Check if already has active assignment for this template (pending or submitted)
        existing_assignment = current_volunteer_profile.task_assignments
                                                       .where(task_template: @task_template)
                                                       .where(status: [:pending, :submitted])
                                                       .first

        if existing_assignment
          status_key = "decidim.volunteer_scheduler.task_assignments.status.#{existing_assignment.status}"
          return t("decidim.volunteer_scheduler.task_assignments.create.already_assigned",
                  task: @task_template.title,
                  status: t(status_key))
        end

        # Check daily task limit
        today_count = current_volunteer_profile.task_assignments
                                              .where("assigned_at >= ?", Time.current.beginning_of_day)
                                              .count
        max_daily = 5  # Default for organization-level tasks

        if today_count >= max_daily
          return t("decidim.volunteer_scheduler.task_assignments.create.daily_limit_reached",
                  limit: max_daily)
        end

        nil # No errors
      end
      
      def calculate_due_date
        deadline_days = 7  # Default for organization-level tasks
        deadline_days.days.from_now
      end

      def submit_assignment
        # Simple approach - just get params directly
        submission_params = {
          submission_notes: params[:task_assignment][:submission_notes],
          hours_worked: params[:task_assignment][:hours_worked],
          challenges_faced: params[:task_assignment][:challenges_faced]
        }

        if @task_assignment.submit_work!(submission_params)
          # Handle attachment uploads using Decidim's attachment system
          if params[:task_assignment][:add_documents].present?
            params[:task_assignment][:add_documents].each do |document|
              next if document.blank?

              Decidim::Attachment.create!(
                attached_to: @task_assignment,
                file: document,
                title: { I18n.locale.to_s => document.original_filename },
                content_type: document.content_type
              )
            end
          end

          redirect_to task_assignment_path(@task_assignment),
                     notice: t("decidim.volunteer_scheduler.task_assignments.submit.success")
        else
          flash[:alert] = t("decidim.volunteer_scheduler.task_assignments.submit.error")
          redirect_to task_assignment_path(@task_assignment)
        end
      rescue => e
        Rails.logger.error "Task submission error: #{e.message}\n#{e.backtrace.join("\n")}"
        flash[:alert] = "Error: #{e.message}"
        redirect_to task_assignment_path(@task_assignment)
      end

      def redirect_with_error(message = nil)
        message ||= "An error occurred"
        redirect_to root_path, alert: message
      end
    end
  end
end
