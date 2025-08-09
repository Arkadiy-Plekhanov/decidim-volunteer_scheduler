# config/routes.rb
Decidim::VolunteerScheduler::Engine.routes.draw do
  scope "/components/:component_id" do
    root to: "dashboard#show"
    
    resources :task_templates, only: [:index, :show] do
      member do
        post :accept
      end
    end
    
    resources :assignments, only: [:index, :show, :update] do
      member do
        patch :start
        patch :submit
        patch :cancel
      end
    end
    
    resources :referrals, only: [:index, :show] do
      collection do
        get :tree
        get :statistics
      end
    end
    
    resources :teams, except: [:destroy] do
      member do
        post :join
        delete :leave
        patch :update_member_role
      end
      
      resources :members, only: [:index, :update, :destroy], controller: 'team_members'
    end
    
    namespace :api do
      resources :assignments, only: [:index, :show]
      resources :statistics, only: [:index] do
        collection do
          get :volunteer_stats
          get :referral_stats
          get :activity_multiplier
        end
      end
    end
  end
end

# Admin routes
Decidim::VolunteerScheduler::AdminEngine.routes.draw do
  scope "/components/:component_id" do
    root to: "dashboard#show"
    
    resources :task_templates do
      collection do
        get :export
        post :import
      end
      
      member do
        patch :toggle_active
      end
    end
    
    resources :assignments, only: [:index, :show, :update] do
      member do
        patch :approve
        patch :reject
        patch :cancel
      end
      
      collection do
        get :pending
        get :overdue
      end
    end
    
    resources :volunteer_profiles, only: [:index, :show, :update] do
      member do
        patch :adjust_xp
        patch :adjust_multiplier
        post :add_achievement
      end
      
      collection do
        get :export
        get :statistics
      end
    end
    
    resources :referrals, only: [:index, :show] do
      member do
        patch :toggle_active
      end
      
      collection do
        get :commission_report
        get :performance_report
      end
    end
    
    resources :scicent_transactions, only: [:index, :show, :create] do
      collection do
        get :export
        post :bulk_create
      end
    end
    
    resources :reports, only: [:index] do
      collection do
        get :engagement
        get :referral_performance
        get :xp_distribution
        get :task_completion_rates
      end
    end
    
    resources :settings, only: [:show, :update] do
      collection do
        get :xp_settings
        patch :update_xp_settings
        get :commission_settings
        patch :update_commission_settings
      end
    end
  end
end

# app/controllers/decidim/volunteer_scheduler/application_controller.rb
module Decidim
  module VolunteerScheduler
    class ApplicationController < Decidim::Components::BaseController
      include Decidim::UserProfile
      
      before_action :ensure_volunteer_profile
      before_action :check_component_permissions
      
      private
      
      def ensure_volunteer_profile
        return unless current_user
        return if current_user.volunteer_profile
        
        # Auto-create profile if enabled in component settings
        if current_component.settings.global["auto_create_profiles"]
          current_user.send(:create_volunteer_profile_with_referral)
        else
          flash[:alert] = t("decidim.volunteer_scheduler.errors.profile_required")
          redirect_to decidim.root_path
        end
      end
      
      def check_component_permissions
        enforce_permission_to :read, :component, component: current_component
      end
      
      def current_volunteer_profile
        @current_volunteer_profile ||= current_user&.volunteer_profile
      end
      helper_method :current_volunteer_profile
      
      def available_task_templates
        @available_task_templates ||= TaskTemplate.available_for_user(current_user)
                                                 .where(component: current_component)
                                                 .page(params[:page])
                                                 .per(12)
      end
      helper_method :available_task_templates
    end
  end
end

# app/controllers/decidim/volunteer_scheduler/dashboard_controller.rb
module Decidim
  module VolunteerScheduler
    class DashboardController < ApplicationController
      def show
        @volunteer_profile = current_volunteer_profile
        @active_assignments = current_user.active_task_assignments
                                         .joins(:task_template)
                                         .where(decidim_volunteer_scheduler_task_templates: { decidim_component_id: current_component.id })
                                         .includes(:task_template)
                                         .limit(5)
        
        @recent_assignments = current_user.completed_task_assignments
                                         .joins(:task_template)
                                         .where(decidim_volunteer_scheduler_task_templates: { decidim_component_id: current_component.id })
                                         .includes(:task_template)
                                         .limit(5)
                                         .order(completed_at: :desc)
        
        @available_tasks = available_task_templates.limit(6)
        @referral_statistics = calculate_referral_statistics
        @recent_transactions = current_user.scicent_transactions
                                          .successful
                                          .limit(5)
                                          .order(created_at: :desc)
      end
      
      private
      
      def calculate_referral_statistics
        return {} unless current_volunteer_profile
        
        {
          total_referrals: current_user.referrals_made.active.count,
          active_referrals: current_volunteer_profile.active_referrals_count,
          total_commission: current_volunteer_profile.total_referral_commission,
          this_month_commission: current_user.scicent_transactions
                                           .where(transaction_type: :referral_commission)
                                           .where(created_at: 1.month.ago..Time.current)
                                           .sum(:amount)
        }
      end
    end
  end
end

# app/controllers/decidim/volunteer_scheduler/task_templates_controller.rb
module Decidim
  module VolunteerScheduler
    class TaskTemplatesController < ApplicationController
      before_action :set_task_template, only: [:show, :accept]
      
      def index
        @task_templates = available_task_templates
        @categories = TaskTemplate.categories.keys
        @levels = [1, 2, 3]
        
        # Apply filters
        @task_templates = @task_templates.by_category(params[:category]) if params[:category].present?
        @task_templates = @task_templates.available_for_level(params[:level]) if params[:level].present?
      end
      
      def show
        @assignment_history = @task_template.task_assignments
                                           .where(assignee: current_user)
                                           .order(assigned_at: :desc)
                                           .limit(5)
      end
      
      def accept
        enforce_permission_to :accept, :task_template, task_template: @task_template
        
        @form = AcceptTaskForm.new
        
        AcceptTask.call(@task_template, current_user) do
          on(:ok) do |assignment|
            flash[:notice] = t("decidim.volunteer_scheduler.task_templates.accept.success")
            redirect_to assignment_path(assignment)
          end
          
          on(:invalid) do |message|
            flash[:alert] = message.presence || t("decidim.volunteer_scheduler.task_templates.accept.error")
            redirect_to task_template_path(@task_template)
          end
        end
      end
      
      private
      
      def set_task_template
        @task_template = TaskTemplate.find(params[:id])
      end
    end
  end
end

# app/controllers/decidim/volunteer_scheduler/assignments_controller.rb
module Decidim
  module VolunteerScheduler
    class AssignmentsController < ApplicationController
      before_action :set_assignment, only: [:show, :update, :start, :submit, :cancel]
      before_action :ensure_assignment_ownership, only: [:show, :update, :start, :submit, :cancel]
      
      def index
        @assignments = current_user.task_assignments
                                  .joins(:task_template)
                                  .where(decidim_volunteer_scheduler_task_templates: { decidim_component_id: current_component.id })
                                  .includes(:task_template)
                                  .order(assigned_at: :desc)
                                  .page(params[:page])
                                  .per(10)
        
        # Apply status filter
        @assignments = @assignments.by_status(params[:status]) if params[:status].present?
      end
      
      def show
        @submission_form = TaskSubmissionForm.new
      end
      
      def start
        if @assignment.start_task!
          flash[:notice] = t("decidim.volunteer_scheduler.assignments.start.success")
        else
          flash[:alert] = t("decidim.volunteer_scheduler.assignments.start.error")
        end
        
        redirect_to assignment_path(@assignment)
      end
      
      def submit
        @submission_form = TaskSubmissionForm.from_params(params[:task_submission])
        
        SubmitTask.call(@assignment, @submission_form, current_user) do
          on(:ok) do
            flash[:notice] = t("decidim.volunteer_scheduler.assignments.submit.success")
            redirect_to assignment_path(@assignment)
          end
          
          on(:invalid) do
            flash.now[:alert] = t("decidim.volunteer_scheduler.assignments.submit.error")
            render :show
          end
        end
      end
      
      def cancel
        reason = params[:reason]
        
        if @assignment.cancel_task!(reason)
          flash[:notice] = t("decidim.volunteer_scheduler.assignments.cancel.success")
          redirect_to assignments_path
        else
          flash[:alert] = t("decidim.volunteer_scheduler.assignments.cancel.error")
          redirect_to assignment_path(@assignment)
        end
      end
      
      private
      
      def set_assignment
        @assignment = TaskAssignment.find(params[:id])
      end
      
      def ensure_assignment_ownership
        unless @assignment.assignee == current_user
          flash[:alert] = t("decidim.volunteer_scheduler.assignments.errors.not_authorized")
          redirect_to assignments_path
        end
      end
    end
  end
end

# app/controllers/decidim/volunteer_scheduler/referrals_controller.rb
module Decidim
  module VolunteerScheduler
    class ReferralsController < ApplicationController
      def index
        @referral_statistics = {
          total_made: current_user.referrals_made.active.count,
          total_received: current_user.referrals_received.active.count,
          active_referrals: current_volunteer_profile.active_referrals_count,
          total_commission: current_volunteer_profile.total_referral_commission,
          referral_code: current_volunteer_profile.referral_code,
          referral_link: current_user.referral_link(current_component)
        }
        
        @recent_referrals = current_user.referrals_made
                                      .active
                                      .includes(:referred)
                                      .order(created_at: :desc)
                                      .limit(10)
        
        @recent_commissions = current_user.scicent_transactions
                                        .where(transaction_type: :referral_commission)
                                        .successful
                                        .limit(10)
                                        .order(created_at: :desc)
      end
      
      def show
        @referral = current_user.referrals_made.find(params[:id])
        @commission_history = @referral.scicent_transactions
                                     .successful
                                     .order(created_at: :desc)
                                     .limit(20)
      end
      
      def tree
        @referral_tree = build_referral_tree
        render json: @referral_tree
      end
      
      def statistics
        render json: {
          total_referrals: current_user.referrals_made.active.count,
          active_referrals: current_volunteer_profile.active_referrals_count,
          total_commission: current_volunteer_profile.total_referral_commission,
          monthly_commission: monthly_commission_stats,
          referral_levels: referral_level_breakdown
        }
      end
      
      private
      
      def build_referral_tree
        # Build a tree structure showing referral relationships
        # This would be used for visualization
        tree = {
          user: {
            id: current_user.id,
            name: current_user.name,
            level: current_volunteer_profile.level,
            referral_code: current_volunteer_profile.referral_code
          },
          referrals: []
        }
        
        current_user.referrals_made.active.includes(:referred).each do |referral|
          tree[:referrals] << {
            id: referral.id,
            user: {
              id: referral.referred.id,
              name: referral.referred.name,
              level: referral.referred.volunteer_profile&.level || 1
            },
            level: referral.level,
            commission_rate: referral.commission_rate,
            total_commission: referral.total_commission,
            created_at: referral.created_at
          }
        end
        
        tree
      end
      
      def monthly_commission_stats
        6.months.ago.to_date.step(Date.current, 1.month).map do |date|
          month_start = date.beginning_of_month
          month_end = date.end_of_month
          
          {
            month: date.strftime("%Y-%m"),
            commission: current_user.scicent_transactions
                                   .where(transaction_type: :referral_commission)
                                   .where(created_at: month_start..month_end)
                                   .sum(:amount)
          }
        end
      end
      
      def referral_level_breakdown
        current_user.referrals_made.active.group(:level).count
      end
    end
  end
end