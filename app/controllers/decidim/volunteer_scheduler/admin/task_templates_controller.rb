# frozen_string_literal: true

module Decidim
  module VolunteerScheduler
    module Admin
      # Controller for managing task templates in admin interface
      class TaskTemplatesController < ApplicationController
        before_action :set_task_template, only: [:show, :edit, :update, :destroy, :publish, :unpublish]

        def index
          @task_templates = paginated_collection
        end

        def show
        end

        def new
          @task_template = TaskTemplate.new
        end

        def edit
        end

        def create
          @task_template = TaskTemplate.new(task_template_params)
          @task_template.organization = current_organization

          if @task_template.save
            redirect_to task_templates_path, notice: t(".success")
          else
            render :new
          end
        end

        def update
          if @task_template.update(task_template_params)
            redirect_to task_templates_path, notice: t(".success")
          else
            render :edit
          end
        end

        def destroy
          @task_template.destroy
          redirect_to task_templates_path, notice: t(".success")
        end

        def publish
          @task_template.update!(status: :published)
          redirect_to task_templates_path, notice: t(".published")
        end

        def unpublish
          @task_template.update!(status: :draft)
          redirect_to task_templates_path, notice: t(".unpublished")
        end

        private

        def paginated_collection
          @paginated_collection ||= TaskTemplate.where(organization: current_organization)
                                               .order(created_at: :desc)
                                               .page(params[:page])
        end

        def set_task_template
          @task_template = TaskTemplate.where(organization: current_organization).find(params[:id])
        end

        def task_template_params
          params.require(:task_template).permit(
            :title, :description, :xp_reward, :level_required, 
            :category, :frequency, :status
          )
        end
      end
    end
  end
end
