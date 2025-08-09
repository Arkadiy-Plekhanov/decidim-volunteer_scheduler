# frozen_string_literal: true

module Decidim
  module VolunteerScheduler
    module Admin
      # Controller for reviewing task assignments in admin interface
      class TaskAssignmentsController < ApplicationController
        before_action :set_task_assignment, only: [:show, :update]

        def index
          @task_assignments = TaskAssignment.joins(:task_template)
                                           .where(decidim_volunteer_scheduler_task_templates: { organization: current_organization })
                                           .includes(:task_template, :assignee)
                                           .order(submitted_at: :desc, assigned_at: :desc)
                                           .page(params[:page])

          @task_assignments = @task_assignments.where(status: params[:status]) if params[:status].present?
        end

        def show
        end

        def update
          case params[:action_type]
          when "approve"
            approve_assignment
          when "reject"
            reject_assignment
          when "bulk_approve"
            bulk_approve_assignments
          when "bulk_reject"
            bulk_reject_assignments
          else
            redirect_with_error("Invalid action")
          end
        end

        def bulk_approve
          assignment_ids = params[:assignment_ids] || []
          approved_count = 0

          assignment_ids.each do |id|
            assignment = TaskAssignment.find(id)
            if AssignmentApprover.new(assignment, current_user, :approve).call
              approved_count += 1
            end
          end

          redirect_to task_assignments_path, 
                     notice: t(".bulk_approved", count: approved_count)
        end

        def bulk_reject
          assignment_ids = params[:assignment_ids] || []
          rejected_count = 0

          assignment_ids.each do |id|
            assignment = TaskAssignment.find(id)
            if AssignmentApprover.new(assignment, current_user, :reject).call
              rejected_count += 1
            end
          end

          redirect_to task_assignments_path, 
                     notice: t(".bulk_rejected", count: rejected_count)
        end

        private

        def set_task_assignment
          @task_assignment = TaskAssignment.joins(:task_template)
                                          .where(decidim_volunteer_scheduler_task_templates: { organization: current_organization })
                                          .find(params[:id])
        end

        def approve_assignment
          approver = AssignmentApprover.new(@task_assignment, current_user, :approve, params[:review_notes])
          
          if approver.call
            redirect_to task_assignment_path(@task_assignment), notice: t(".approved")
          else
            redirect_with_error("Failed to approve assignment")
          end
        end

        def reject_assignment
          approver = AssignmentApprover.new(@task_assignment, current_user, :reject, params[:review_notes])
          
          if approver.call
            redirect_to task_assignment_path(@task_assignment), notice: t(".rejected")
          else
            redirect_with_error("Failed to reject assignment")
          end
        end

        def redirect_with_error(message)
          redirect_to task_assignments_path, alert: message
        end
      end
    end
  end
end
