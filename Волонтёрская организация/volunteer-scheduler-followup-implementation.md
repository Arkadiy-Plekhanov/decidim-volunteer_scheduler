# Decidim Volunteer Scheduler - Follow-up Integration Implementation Guide

## Priority 1: Follow-up System for Task Submissions

### Core Architecture Decision

**Use Decidim's native follow-up system** for task submissions rather than building a custom submission system. This provides:
- Built-in UI components for submissions
- Existing notification infrastructure
- Admin review interfaces
- Audit trail and versioning

### Implementation Pattern

```ruby
# app/models/decidim/volunteer_scheduler/task_assignment.rb
module Decidim
  module VolunteerScheduler
    class TaskAssignment < ApplicationRecord
      include Decidim::Followable
      include Decidim::HasComponent
      include Decidim::Traceable
      include Decidim::Loggable
      
      belongs_to :task_template,
                 class_name: "Decidim::VolunteerScheduler::TaskTemplate",
                 foreign_key: "decidim_task_template_id"
      
      belongs_to :assignee,
                 class_name: "Decidim::User",
                 foreign_key: "decidim_user_id"
      
      # Use Decidim's follow-up for submissions
      has_many :follow_ups,
               -> { where(followable_type: "Decidim::VolunteerScheduler::TaskAssignment") },
               foreign_key: :followable_id,
               class_name: "Decidim::FollowUp",
               dependent: :destroy
               
      # State machine for assignment workflow
      enum status: {
        pending: 0,      # Task accepted, not started
        in_progress: 1,  # Volunteer working on task
        submitted: 2,    # Follow-up submitted for review
        approved: 3,     # Admin approved submission
        rejected: 4      # Admin rejected submission
      }
      
      # Automatically create follow relationship when assignment created
      after_create :auto_follow_assignment
      
      def latest_submission
        follow_ups.order(created_at: :desc).first
      end
      
      def submit_work!(submission_params)
        transaction do
          # Create follow-up record
          follow_up = Decidim::FollowUp.create!(
            followable: self,
            user: assignee,
            body: submission_params[:report],
            metadata: {
              hours_worked: submission_params[:hours_worked],
              attachments: submission_params[:attachments],
              submitted_at: Time.current
            }
          )
          
          # Update assignment status
          update!(status: :submitted, submitted_at: Time.current)
          
          # Trigger notification to admin
          Decidim::EventsManager.publish(
            event: "decidim.volunteer_scheduler.task_submitted",
            event_class: TaskSubmittedEvent,
            resource: self,
            followers: component.admins,
            extra: {
              volunteer_name: assignee.name,
              task_title: task_template.title
            }
          )
          
          follow_up
        end
      end
      
      def approve!(admin_user, notes = nil)
        transaction do
          # Update status
          update!(
            status: :approved,
            approved_at: Time.current,
            approved_by: admin_user.id,
            admin_notes: notes
          )
          
          # Award XP
          volunteer_profile = assignee.volunteer_profile
          volunteer_profile.add_xp(task_template.xp_reward)
          
          # Create admin follow-up
          Decidim::FollowUp.create!(
            followable: self,
            user: admin_user,
            body: "Task approved. #{notes}",
            metadata: {
              action: "approved",
              xp_awarded: task_template.xp_reward
            }
          )
          
          # Notify volunteer
          Decidim::EventsManager.publish(
            event: "decidim.volunteer_scheduler.task_approved",
            event_class: TaskApprovedEvent,
            resource: self,
            followers: [assignee]
          )
        end
      end
      
      private
      
      def auto_follow_assignment
        Decidim::Follow.create!(
          followable: self,
          user: assignee
        )
      end
    end
  end
end
```

### Follow-up Submission Controller

```ruby
# app/controllers/decidim/volunteer_scheduler/task_submissions_controller.rb
module Decidim
  module VolunteerScheduler
    class TaskSubmissionsController < ApplicationController
      include Decidim::FormFactory
      
      before_action :authenticate_user!
      before_action :find_assignment
      before_action :ensure_can_submit
      
      def new
        @form = form(TaskSubmissionForm).instance
      end
      
      def create
        @form = form(TaskSubmissionForm).from_params(params)
        
        SubmitTaskWork.call(@form, current_user, @assignment) do
          on(:ok) do |follow_up|
            flash[:notice] = t(".success")
            redirect_to volunteer_dashboard_path
          end
          
          on(:invalid) do
            flash.now[:alert] = t(".invalid")
            render :new
          end
        end
      end
      
      private
      
      def find_assignment
        @assignment = TaskAssignment.find(params[:task_assignment_id])
      end
      
      def ensure_can_submit
        redirect_to volunteer_dashboard_path unless can_submit?
      end
      
      def can_submit?
        @assignment.assignee == current_user &&
          @assignment.pending? || @assignment.in_progress?
      end
    end
  end
end
```

### Submission Form Using Follow-up Pattern

```erb
<!-- app/views/decidim/volunteer_scheduler/task_submissions/new.html.erb -->
<div class="row">
  <div class="columns large-8 large-centered">
    <div class="card">
      <div class="card__content">
        <h2><%= t(".title", task: @assignment.task_template.title) %></h2>
        
        <%= decidim_form_for @form, url: task_assignment_submissions_path(@assignment), html: { class: "form" } do |f| %>
          
          <div class="field">
            <%= f.label :report %>
            <%= f.text_area :report, rows: 10, required: true %>
            <p class="help-text"><%= t(".report_help") %></p>
          </div>
          
          <div class="field">
            <%= f.label :hours_worked %>
            <%= f.number_field :hours_worked, step: 0.25, min: 0, required: true %>
          </div>
          
          <div class="field">
            <%= f.label :challenges_faced %>
            <%= f.text_area :challenges_faced, rows: 5 %>
          </div>
          
          <div class="field">
            <%= f.label :attachments %>
            <%= f.upload :attachments, multiple: true %>
            <p class="help-text"><%= t(".attachments_help") %></p>
          </div>
          
          <div class="actions">
            <%= f.submit t(".submit"), class: "button button--highlight" %>
            <%= link_to t(".cancel"), volunteer_dashboard_path, class: "button button--text" %>
          </div>
          
        <% end %>
      </div>
    </div>
  </div>
</div>
```

## Priority 2: Organization-Level Task Templates

### Database Architecture

```ruby
# db/migrate/001_create_decidim_volunteer_scheduler_task_templates.rb
class CreateDecidimVolunteerSchedulerTaskTemplates < ActiveRecord::Migration[6.1]
  def change
    create_table :decidim_volunteer_scheduler_task_templates do |t|
      # Organization-level, not component-level
      t.references :decidim_organization, null: false, foreign_key: true, index: true
      
      # Multilingual fields
      t.jsonb :title, null: false
      t.jsonb :description, null: false
      t.jsonb :instructions
      
      # Task configuration
      t.integer :level_requirement, null: false, default: 1
      t.integer :xp_reward, null: false, default: 10
      t.integer :scicent_reward, default: 0
      t.integer :estimated_hours, default: 1
      t.integer :max_assignments_per_user, default: 1
      
      # Frequency and availability
      t.integer :frequency, null: false, default: 0 # enum: daily, weekly, monthly, one_time
      t.boolean :active, default: true
      t.datetime :available_from
      t.datetime :available_until
      
      # Categorization (using Decidim 0.30+ Taxonomy)
      t.string :category_key
      t.jsonb :metadata, default: {}
      
      t.timestamps
      
      t.index [:decidim_organization_id, :active]
      t.index [:level_requirement]
      t.index [:frequency]
    end
  end
end
```

### Organization-Level Model

```ruby
# app/models/decidim/volunteer_scheduler/task_template.rb
module Decidim
  module VolunteerScheduler
    class TaskTemplate < ApplicationRecord
      include Decidim::TranslatableResource
      include Decidim::Traceable
      include Decidim::Loggable
      
      # Organization-level association
      belongs_to :organization,
                 class_name: "Decidim::Organization",
                 foreign_key: "decidim_organization_id"
      
      # Templates can be used across multiple components
      has_many :task_assignments,
               class_name: "Decidim::VolunteerScheduler::TaskAssignment",
               foreign_key: "decidim_task_template_id",
               dependent: :restrict_with_error
      
      translatable_fields :title, :description, :instructions
      
      enum frequency: {
        one_time: 0,
        daily: 1,
        weekly: 2,
        monthly: 3
      }
      
      validates :title, :description, translatable_presence: true
      validates :level_requirement, presence: true, inclusion: { in: 1..3 }
      validates :xp_reward, presence: true, numericality: { greater_than: 0 }
      
      scope :active, -> { where(active: true) }
      scope :available_now, -> {
        where("(available_from IS NULL OR available_from <= ?) AND 
               (available_until IS NULL OR available_until >= ?)", 
               Time.current, Time.current)
      }
      scope :for_level, ->(level) { where("level_requirement <= ?", level) }
      scope :for_organization, ->(org) { where(decidim_organization_id: org.id) }
      
      # Check if user can accept this template
      def available_for_user?(user)
        return false unless active? && available_now?
        
        profile = user.volunteer_profile
        return false unless profile
        return false if profile.level < level_requirement
        
        # Check assignment limit
        if max_assignments_per_user > 0
          existing_count = task_assignments
                          .where(assignee: user)
                          .where.not(status: [:rejected])
                          .count
          return false if existing_count >= max_assignments_per_user
        end
        
        true
      end
      
      def available_now?
        now = Time.current
        (available_from.nil? || available_from <= now) &&
          (available_until.nil? || available_until >= now)
      end
    end
  end
end
```

### Admin Interface for Organization-Level Templates

```ruby
# app/controllers/decidim/volunteer_scheduler/admin/task_templates_controller.rb
module Decidim
  module VolunteerScheduler
    module Admin
      class TaskTemplatesController < Decidim::Admin::ApplicationController
        layout "decidim/admin/volunteer_scheduler"
        
        # Organization-level permissions
        before_action :ensure_organization_admin
        
        def index
          @task_templates = current_organization
                           .task_templates
                           .includes(:task_assignments)
                           .page(params[:page])
                           .per(15)
        end
        
        def new
          enforce_permission_to :create, :task_template
          @form = form(TaskTemplateForm).instance
        end
        
        def create
          enforce_permission_to :create, :task_template
          @form = form(TaskTemplateForm).from_params(params)
          
          CreateTaskTemplate.call(@form, current_organization, current_user) do
            on(:ok) do
              flash[:notice] = I18n.t("task_templates.create.success", 
                                     scope: "decidim.volunteer_scheduler.admin")
              redirect_to admin_task_templates_path
            end
            
            on(:invalid) do
              flash.now[:alert] = I18n.t("task_templates.create.invalid", 
                                         scope: "decidim.volunteer_scheduler.admin")
              render :new
            end
          end
        end
        
        private
        
        def ensure_organization_admin
          enforce_permission_to :manage, :organization
        end
      end
    end
  end
end
```

## Priority 3: Optimal Decidim Integration Pattern

### Best Practice: Separate Profile Model with User Association

After analyzing Decidim's patterns, **creating a separate VolunteerProfile model** is better than extending User directly because:

1. **Clean separation of concerns**
2. **Component-scoped data**
3. **Easier testing and maintenance**
4. **No core modifications needed**

```ruby
# app/models/decidim/volunteer_scheduler/volunteer_profile.rb
module Decidim
  module VolunteerScheduler
    class VolunteerProfile < ApplicationRecord
      include Decidim::Traceable
      
      belongs_to :user,
                 class_name: "Decidim::User",
                 foreign_key: "decidim_user_id"
      
      belongs_to :organization,
                 class_name: "Decidim::Organization",
                 foreign_key: "decidim_organization_id"
      
      # Component association for participation context
      belongs_to :component,
                 class_name: "Decidim::Component",
                 foreign_key: "decidim_component_id",
                 optional: true
      
      has_many :task_assignments,
               class_name: "Decidim::VolunteerScheduler::TaskAssignment",
               foreign_key: "decidim_user_id",
               primary_key: "decidim_user_id"
      
      validates :user_id, uniqueness: { scope: [:organization_id, :component_id] }
      validates :referral_code, uniqueness: true, allow_nil: true
      
      before_create :generate_referral_code
      
      # XP and Level System
      def add_xp(amount)
        self.total_xp += amount
        calculate_level!
        save!
        
        # Check for level up
        if level_changed?
          notify_level_up
        end
      end
      
      def calculate_level!
        self.level = case total_xp
                    when 0..99 then 1
                    when 100..499 then 2
                    else 3
                    end
      end
      
      private
      
      def generate_referral_code
        loop do
          self.referral_code = SecureRandom.alphanumeric(8).upcase
          break unless self.class.exists?(referral_code: referral_code)
        end
      end
      
      def notify_level_up
        Decidim::EventsManager.publish(
          event: "decidim.volunteer_scheduler.level_up",
          event_class: LevelUpEvent,
          resource: self,
          followers: [user],
          extra: {
            new_level: level,
            new_capabilities: level_capabilities
          }
        )
      end
      
      def level_capabilities
        case level
        when 1
          ["Accept basic tasks", "Submit reports"]
        when 2
          ["Accept intermediate tasks", "Create teams", "Mentor new volunteers"]
        when 3
          ["Accept all tasks", "Lead initiatives", "Admin assistance"]
        else
          []
        end
      end
    end
  end
end
```

### User Extension via Concern (Lightweight)

```ruby
# app/models/concerns/decidim/volunteer_scheduler/user_extensions.rb
module Decidim
  module VolunteerScheduler
    module UserExtensions
      extend ActiveSupport::Concern
      
      included do
        has_one :volunteer_profile,
                -> { where(component_id: nil) }, # Organization-wide profile
                class_name: "Decidim::VolunteerScheduler::VolunteerProfile",
                foreign_key: "decidim_user_id",
                dependent: :destroy
        
        has_many :component_volunteer_profiles,
                 class_name: "Decidim::VolunteerScheduler::VolunteerProfile",
                 foreign_key: "decidim_user_id",
                 dependent: :destroy
        
        has_many :volunteer_task_assignments,
                 class_name: "Decidim::VolunteerScheduler::TaskAssignment",
                 foreign_key: "decidim_user_id"
      end
      
      # Get or create volunteer profile for a specific context
      def volunteer_profile_for(organization, component = nil)
        profile = component_volunteer_profiles.find_by(
          decidim_organization_id: organization.id,
          decidim_component_id: component&.id
        )
        
        unless profile
          profile = component_volunteer_profiles.create!(
            decidim_organization_id: organization.id,
            decidim_component_id: component&.id,
            level: 1,
            total_xp: 0
          )
        end
        
        profile
      end
      
      def total_volunteer_hours
        volunteer_task_assignments
          .approved
          .joins(:follow_ups)
          .sum("(follow_ups.metadata->>'hours_worked')::float")
      end
    end
  end
end

# Apply the concern in an initializer
# config/initializers/decidim_volunteer_scheduler.rb
Rails.application.config.to_prepare do
  Decidim::User.include(Decidim::VolunteerScheduler::UserExtensions)
end
```

## Complete Integration Flow

### 1. Task Acceptance Flow

```ruby
# app/commands/decidim/volunteer_scheduler/accept_task.rb
module Decidim
  module VolunteerScheduler
    class AcceptTask < Decidim::Command
      def initialize(task_template, user, component)
        @task_template = task_template
        @user = user
        @component = component
      end
      
      def call
        return broadcast(:invalid) unless can_accept?
        
        transaction do
          create_assignment
          create_follow_relationship
          send_notifications
        end
        
        broadcast(:ok, @assignment)
      end
      
      private
      
      def can_accept?
        @task_template.available_for_user?(@user)
      end
      
      def create_assignment
        @assignment = TaskAssignment.create!(
          task_template: @task_template,
          assignee: @user,
          component: @component,
          status: :pending,
          assigned_at: Time.current,
          due_date: calculate_due_date
        )
      end
      
      def create_follow_relationship
        # Auto-follow the assignment for updates
        Decidim::Follow.create!(
          followable: @assignment,
          user: @user
        )
      end
      
      def send_notifications
        Decidim::EventsManager.publish(
          event: "decidim.volunteer_scheduler.task_accepted",
          event_class: TaskAcceptedEvent,
          resource: @assignment,
          followers: [@user],
          extra: {
            task_title: @task_template.title,
            due_date: @assignment.due_date
          }
        )
      end
      
      def calculate_due_date
        case @task_template.frequency
        when "daily"
          1.day.from_now
        when "weekly"
          1.week.from_now
        when "monthly"
          1.month.from_now
        else
          7.days.from_now # default
        end
      end
    end
  end
end
```

### 2. Admin Review Interface

```erb
<!-- app/views/decidim/volunteer_scheduler/admin/task_assignments/index.html.erb -->
<div class="card">
  <div class="card-divider">
    <h2 class="card-title">
      <%= t(".title") %>
      <span class="label label--basic"><%= @pending_count %> <%= t(".pending") %></span>
    </h2>
  </div>
  
  <div class="card-section">
    <div class="table-scroll">
      <table class="table-list">
        <thead>
          <tr>
            <th><%= t(".volunteer") %></th>
            <th><%= t(".task") %></th>
            <th><%= t(".submitted_at") %></th>
            <th><%= t(".report") %></th>
            <th><%= t(".hours") %></th>
            <th><%= t(".actions") %></th>
          </tr>
        </thead>
        <tbody>
          <% @assignments.each do |assignment| %>
            <% submission = assignment.latest_submission %>
            <tr>
              <td>
                <%= link_to assignment.assignee.name, 
                    admin_volunteer_path(assignment.assignee) %>
              </td>
              <td><%= translated_attribute(assignment.task_template.title) %></td>
              <td><%= l(assignment.submitted_at, format: :short) if assignment.submitted_at %></td>
              <td>
                <% if submission %>
                  <%= truncate(submission.body, length: 100) %>
                  <%= link_to t(".view_full"), "#", 
                      data: { toggle: "submission-#{assignment.id}" } %>
                <% end %>
              </td>
              <td><%= submission&.metadata&.dig("hours_worked") %></td>
              <td class="table-list__actions">
                <% if assignment.submitted? %>
                  <%= link_to t(".approve"), 
                      approve_admin_task_assignment_path(assignment),
                      method: :post,
                      class: "action-icon action-icon--approve",
                      data: { confirm: t(".confirm_approve") } %>
                  
                  <%= link_to t(".reject"),
                      reject_admin_task_assignment_path(assignment),
                      method: :post,
                      class: "action-icon action-icon--reject",
                      data: { confirm: t(".confirm_reject") } %>
                <% end %>
              </td>
            </tr>
            
            <!-- Hidden full report -->
            <tr id="submission-<%= assignment.id %>" style="display: none;">
              <td colspan="6">
                <div class="callout secondary">
                  <h4><%= t(".full_report") %></h4>
                  <%= simple_format(submission&.body) %>
                  
                  <% if submission&.metadata&.dig("attachments").present? %>
                    <h5><%= t(".attachments") %></h5>
                    <!-- Render attachments -->
                  <% end %>
                </div>
              </td>
            </tr>
          <% end %>
        </tbody>
      </table>
    </div>
  </div>
</div>
```

### 3. Component Registration with Follow-up Support

```ruby
# lib/decidim/volunteer_scheduler/component.rb
Decidim.register_component(:volunteer_scheduler) do |component|
  component.engine = Decidim::VolunteerScheduler::Engine
  component.admin_engine = Decidim::VolunteerScheduler::AdminEngine
  component.icon = "decidim/volunteer_scheduler/icon.svg"
  
  # Global settings
  component.settings(:global) do |settings|
    settings.attribute :enable_follow_ups, type: :boolean, default: true
    settings.attribute :require_submission_approval, type: :boolean, default: true
    settings.attribute :auto_approve_after_days, type: :integer, default: 0
    settings.attribute :max_submission_attachments, type: :integer, default: 5
    settings.attribute :enable_peer_review, type: :boolean, default: false
  end
  
  # Register follow-up support
  component.register_resource(:task_assignment) do |resource|
    resource.model_class_name = "Decidim::VolunteerScheduler::TaskAssignment"
    resource.actions = %w(accept submit approve reject follow)
  end
  
  # Stats for component
  component.register_stat :total_assignments do |components, start_at, end_at|
    assignments = Decidim::VolunteerScheduler::TaskAssignment
                  .where(component: components)
    assignments = assignments.where("created_at >= ?", start_at) if start_at
    assignments = assignments.where("created_at <= ?", end_at) if end_at
    assignments.count
  end
  
  component.register_stat :approved_assignments do |components, start_at, end_at|
    assignments = Decidim::VolunteerScheduler::TaskAssignment
                  .where(component: components, status: :approved)
    assignments = assignments.where("approved_at >= ?", start_at) if start_at
    assignments = assignments.where("approved_at <= ?", end_at) if end_at
    assignments.count
  end
  
  # Seeds for development
  component.seeds do |participatory_space|
    organization = participatory_space.organization
    
    # Create sample task templates at org level
    3.times do |i|
      Decidim::VolunteerScheduler::TaskTemplate.create!(
        organization: organization,
        title: { en: "Sample Task #{i + 1}" },
        description: { en: "Description for sample task #{i + 1}" },
        level_requirement: (i % 3) + 1,
        xp_reward: (i + 1) * 10,
        frequency: [:daily, :weekly, :monthly][i % 3],
        active: true
      )
    end
  end
end
```

## Key Implementation Decisions

### 1. Follow-up System (Priority 1)
- **Use native Decidim follow-ups** for task submissions
- Provides built-in UI, notifications, and admin tools
- Maintains consistency with platform patterns

### 2. Organization-Level Templates (Priority 2)
- Templates belong to organization, not component
- Enables reuse across participatory spaces
- Reduces duplication and improves maintenance

### 3. User Integration (Priority 3)
- **Separate VolunteerProfile model** is better than User extension
- Clean separation of concerns
- Component-scoped participation tracking
- No core modifications needed

This architecture provides maximum integration with Decidim while maintaining clean boundaries and following platform conventions.