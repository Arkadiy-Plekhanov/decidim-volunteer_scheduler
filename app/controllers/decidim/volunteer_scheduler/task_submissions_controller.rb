# frozen_string_literal: true

module Decidim
  module VolunteerScheduler
    # Controller for task submission through follow-up system
    class TaskSubmissionsController < ApplicationController
      include Decidim::FormFactory

      before_action :authenticate_user!
      before_action :ensure_volunteer_profile
      before_action :find_assignment
      before_action :ensure_can_submit

      def new
        enforce_permission_to :create, :task_submission, task_assignment: @assignment
        @form = form(TaskSubmissionForm).instance
      end

      def create
        enforce_permission_to :create, :task_submission, task_assignment: @assignment
        @form = form(TaskSubmissionForm).from_params(params)
        
        SubmitTaskWork.call(@form, current_user, @assignment) do
          on(:ok) do |assignment|
            flash[:notice] = I18n.t("task_submissions.create.success", scope: "decidim.volunteer_scheduler")
            redirect_to task_assignment_path(assignment)
          end
          
          on(:invalid) do
            flash.now[:alert] = I18n.t("task_submissions.create.invalid", scope: "decidim.volunteer_scheduler")
            render :new
          end
        end
      end

      private

      def find_assignment
        @assignment = current_volunteer_profile.task_assignments.find(params[:task_assignment_id])
      rescue ActiveRecord::RecordNotFound
        flash[:alert] = I18n.t("task_assignments.not_found", scope: "decidim.volunteer_scheduler")
        redirect_to root_path
      end

      def ensure_can_submit
        unless @assignment.can_be_submitted? && @assignment.assignee == current_volunteer_profile
          flash[:alert] = I18n.t("task_submissions.cannot_submit", scope: "decidim.volunteer_scheduler")
          redirect_to task_assignment_path(@assignment)
        end
      end
    end
  end
end