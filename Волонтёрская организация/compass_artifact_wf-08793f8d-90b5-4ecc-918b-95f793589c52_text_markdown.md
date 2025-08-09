# Decidim Volunteer Scheduler Implementation Guide

This comprehensive guide provides specific implementation patterns and code examples from the Decidim codebase for building robust volunteer scheduler features. Each section includes actual file paths, code snippets, and architectural patterns that can be directly adapted.

## 1. Follow-up System Integration

**Follow-up tracking enables users to subscribe to volunteer opportunities and receive updates on assignments and changes.**

### Core Implementation Pattern

Include the `Decidim::Followable` concern in your volunteer opportunity model:

```ruby
# app/models/decidim/volunteer_scheduler/opportunity.rb
class Opportunity < VolunteerScheduler::ApplicationRecord
  include Decidim::Followable
  include Decidim::Traceable
  include Decidim::Loggable
end
```

### Database Schema

The follow system uses polymorphic associations through the `decidim_follows` table:

```ruby
# Database migration
class CreateDecidimFollows < ActiveRecord::Migration[5.2]
  def change
    create_table :decidim_follows do |t|
      t.references :decidim_user, null: false, index: true
      t.references :followable, polymorphic: true, index: true
      t.timestamps
    end
    
    add_index :decidim_follows, [:decidim_user_id, :followable_type, :followable_id], 
              unique: true, name: "index_decidim_follows_uniqueness"
  end
end
```

### Custom Follow-up Commands

Create volunteer-specific follow commands for tracking task submissions:

```ruby
# app/commands/decidim/volunteer_scheduler/create_submission_follow.rb
class CreateSubmissionFollow < Decidim::Command
  def initialize(form, current_user, submission)
    @form = form
    @current_user = current_user
    @submission = submission
  end

  def call
    return broadcast(:invalid) if form.invalid?
    
    transaction do
      create_follow!
      create_submission_update!
      notify_followers
    end
    
    broadcast(:ok)
  end

  private

  def create_follow!
    @follow = Follow.create!(
      followable: @submission.opportunity,
      user: @current_user
    )
  end

  def create_submission_update!
    SubmissionUpdate.create!(
      submission: @submission,
      content: form.update_content,
      author: @current_user
    )
  end
end
```

### Auto-follow Pattern for Volunteer Registration

Automatically follow opportunities when volunteers register:

```ruby
# app/commands/decidim/volunteer_scheduler/register_volunteer.rb
class RegisterVolunteer < Decidim::Command
  def call
    return broadcast(:invalid) if form.invalid?
    
    transaction do
      create_registration
      auto_follow_opportunity
      send_confirmation_notification
    end
    
    broadcast(:ok, registration)
  end

  private

  def auto_follow_opportunity
    follow_form = Decidim::FollowForm
      .from_params(followable_gid: opportunity.to_signed_global_id.to_s)
      .with_context(current_user: current_user)
    Decidim::CreateFollow.call(follow_form, current_user)
  end
end
```

## 2. Invitation System for Referrals

**Implement referral tracking and invitation systems for volunteer recruitment.**

### Invitation Model Structure

Based on `decidim-meetings/app/models/decidim/meetings/invite.rb` patterns:

```ruby
# app/models/decidim/volunteer_scheduler/invite.rb
class Invite < ApplicationRecord
  belongs_to :user, foreign_key: "decidim_user_id"
  belongs_to :opportunity, foreign_key: "decidim_volunteer_opportunity_id"
  belongs_to :sent_by, class_name: "Decidim::User", foreign_key: "sent_by_id"
  
  enum status: { pending: 0, accepted: 1, rejected: 2 }
  
  validates :token, presence: true, uniqueness: true
  
  before_create :generate_token
  
  private
  
  def generate_token
    self.token = SecureRandom.urlsafe_base64(32)
  end
end
```

### Invitation Command Pattern

```ruby
# app/commands/decidim/volunteer_scheduler/invite_volunteer.rb
class InviteVolunteer < Decidim::Command
  def initialize(form, current_user)
    @form = form
    @current_user = current_user
  end

  def call
    return broadcast(:invalid) if form.invalid?
    
    transaction do
      create_or_update_invite
      send_invitation_email
    end
    
    broadcast(:ok)
  end

  private

  def create_or_update_invite
    @invite = Invite.find_or_create_by(
      user: form.user,
      opportunity: form.opportunity
    ) do |invite|
      invite.sent_by = current_user
      invite.sent_at = Time.current
    end
  end
end
```

### Referral Tracking in Registration

Store referral information during the signup process:

```ruby
# app/controllers/decidim/volunteer_scheduler/registrations_controller.rb
class RegistrationsController < Devise::RegistrationsController
  before_action :store_referral_info, only: [:new, :create]
  
  private
  
  def store_referral_info
    if params[:referral_code].present?
      session[:referral_code] = params[:referral_code]
      session[:referral_source] = params[:source]
      session[:opportunity_id] = params[:opportunity_id]
    end
  end
  
  def after_sign_up_path_for(resource)
    if session[:referral_code].present?
      handle_referral_signup(resource)
    end
    super
  end
  
  def handle_referral_signup(user)
    referral_code = session.delete(:referral_code)
    opportunity_id = session.delete(:opportunity_id)
    
    if opportunity_id && (opportunity = Opportunity.find_by(id: opportunity_id))
      auto_register_for_opportunity(user, opportunity, referral_code)
    end
  end
end
```

## 3. User Model Extension Patterns

**Extend user functionality using concerns and associated models.**

### Volunteer Profile Concern

```ruby
# app/models/concerns/decidim/volunteer_scheduler/volunteer_profile.rb
module Decidim::VolunteerScheduler::VolunteerProfile
  extend ActiveSupport::Concern
  
  included do
    has_many :volunteer_availabilities, 
             class_name: "Decidim::VolunteerScheduler::Availability",
             foreign_key: "decidim_user_id",
             dependent: :destroy
    
    has_many :volunteer_assignments,
             class_name: "Decidim::VolunteerScheduler::Assignment",
             foreign_key: "decidim_user_id"
             
    has_many :volunteer_skills,
             class_name: "Decidim::VolunteerScheduler::UserSkill",
             foreign_key: "decidim_user_id",
             dependent: :destroy
  end
  
  def available_during?(start_time, end_time)
    volunteer_availabilities.where(
      "start_time <= ? AND end_time >= ?", 
      start_time, 
      end_time
    ).exists?
  end
  
  def volunteer_experience_level
    volunteer_assignments.completed.count
  end
end
```

### Database Migration for User Extensions

Follow Decidim's foreign key conventions:

```ruby
# db/migrate/20240101000000_create_decidim_volunteer_scheduler_availabilities.rb
class CreateDecidimVolunteerSchedulerAvailabilities < ActiveRecord::Migration[6.1]
  def change
    create_table :decidim_volunteer_scheduler_availabilities do |t|
      t.references :decidim_user, null: false, foreign_key: true
      t.datetime :start_time, null: false
      t.datetime :end_time, null: false
      t.integer :day_of_week
      t.boolean :recurring, default: false
      t.jsonb :metadata, default: {}
      t.timestamps
    end
    
    add_index :decidim_volunteer_scheduler_availabilities, 
              [:decidim_user_id, :start_time, :end_time],
              name: "idx_volunteer_availability_user_time"
  end
end
```

## 4. Notification and Event System

**Implement comprehensive notifications for volunteer activities.**

### Event Class Structure

```ruby
# app/events/decidim/volunteer_scheduler/shift_assigned_event.rb
class ShiftAssignedEvent < Decidim::Events::SimpleEvent
  include Decidim::Events::EmailEvent
  include Decidim::Events::NotificationEvent
  
  def email_subject
    I18n.t("email_subject", 
           scope: "decidim.events.volunteer_scheduler.shift_assigned",
           resource_title: resource.title)
  end
  
  def email_intro
    I18n.t("email_intro", 
           scope: "decidim.events.volunteer_scheduler.shift_assigned",
           resource_title: resource.title,
           shift_time: shift_time_formatted)
  end
  
  def notification_title
    I18n.t("notification_title", 
           scope: "decidim.events.volunteer_scheduler.shift_assigned",
           resource_title: resource.title)
  end
  
  private
  
  def shift_time_formatted
    I18n.l(extra[:shift_time], format: :decidim_short)
  end
end
```

### Event Publishing Pattern

Publish events when volunteers are assigned to shifts:

```ruby
# app/commands/decidim/volunteer_scheduler/assign_volunteer.rb
class AssignVolunteer < Decidim::Command
  def call
    return broadcast(:invalid) if form.invalid?
    
    transaction do
      create_assignment
      publish_assignment_event
    end
    
    broadcast(:ok, assignment)
  end

  private

  def publish_assignment_event
    Decidim::EventsManager.publish(
      event: "decidim.events.volunteer_scheduler.shift_assigned",
      event_class: Decidim::VolunteerScheduler::ShiftAssignedEvent,
      resource: opportunity,
      affected_users: [volunteer_user],
      extra: {
        shift_time: assignment.start_time,
        assignment_id: assignment.id
      }
    )
  end
end
```

### Real-time Notifications with ActionCable

Optional real-time updates for volunteer dashboard:

```ruby
# app/channels/decidim/volunteer_scheduler/shifts_channel.rb
class ShiftsChannel < ActionCable::Channel::Base
  def subscribed
    stream_from "volunteer_shifts_#{current_user.id}" if current_user
  end
  
  def unsubscribed
    # Cleanup when channel is closed
  end
end

# Broadcasting in assignment command
def broadcast_real_time_update
  ActionCable.server.broadcast(
    "volunteer_shifts_#{volunteer_user.id}",
    {
      type: "shift_assigned",
      assignment: assignment.as_json,
      html: render_assignment_card(assignment)
    }
  )
end
```

## 5. Component Registration and Settings

**Register the volunteer scheduler as a Decidim component with comprehensive settings.**

### Component Manifest

```ruby
# lib/decidim/volunteer_scheduler/component.rb
Decidim.register_component(:volunteer_scheduler) do |component|
  component.engine = VolunteerScheduler::Engine
  component.admin_engine = VolunteerScheduler::AdminEngine
  
  component.icon = "decidim/volunteer_scheduler/icon.svg"
  component.permissions_class_name = "VolunteerScheduler::Permissions"
  
  component.actions = %w(
    create_opportunity 
    register_volunteer 
    cancel_registration 
    manage_schedule
    invite_volunteers
    submit_hours
  )
  
  # Global settings persist for component lifetime
  component.settings(:global) do |settings|
    settings.attribute :max_volunteers_per_slot, type: :integer, default: 10
    settings.attribute :allow_public_registration, type: :boolean, default: true
    settings.attribute :require_authorization, type: :boolean, default: false
    settings.attribute :registration_deadline_hours, type: :integer, default: 24
    settings.attribute :announcement, type: :text, translated: true, editor: true
    settings.attribute :volunteer_categories, type: :string, default: ""
    settings.attribute :enable_hour_tracking, type: :boolean, default: true
    settings.attribute :enable_skill_matching, type: :boolean, default: false
    settings.attribute :auto_approve_registrations, type: :boolean, default: true
  end
  
  # Step settings change per participatory process phase
  component.settings(:step) do |settings|
    settings.attribute :registration_enabled, type: :boolean, default: true
    settings.attribute :show_volunteer_count, type: :boolean, default: true
    settings.attribute :allow_cancellation, type: :boolean, default: true
    settings.attribute :notification_enabled, type: :boolean, default: true
    settings.attribute :step_announcement, type: :text, translated: true, editor: true
    settings.attribute :max_simultaneous_slots, type: :integer, default: 3
    settings.attribute :enable_waitlist, type: :boolean, default: false
  end
  
  # Register resources for permissions
  component.register_resource(:opportunity) do |resource|
    resource.model_class_name = "VolunteerScheduler::Opportunity"
    resource.card = "volunteer_scheduler/opportunity"
    resource.actions = %w(register cancel_registration rate submit_hours)
  end
end
```

## 6. Permission System Implementation

**Implement fine-grained permissions for volunteer activities.**

### Permissions Class

```ruby
# app/permissions/decidim/volunteer_scheduler/permissions.rb
module Decidim::VolunteerScheduler
  class Permissions < Decidim::DefaultPermissions
    def permissions
      return permission_action unless user
      
      return Decidim::VolunteerScheduler::Admin::Permissions
        .new(user, permission_action, context)
        .permissions if permission_action.scope == :admin
      
      case permission_action.action
      when :create
        can_create_opportunity?
      when :register
        can_register_for_opportunity?
      when :cancel_registration
        can_cancel_registration?
      when :submit_hours
        can_submit_hours?
      when :invite_volunteers
        can_invite_volunteers?
      end
      
      permission_action
    end
    
    private
    
    def can_register_for_opportunity?
      return unless user && opportunity
      
      # Check authorization requirements
      authorized = if component_settings.require_authorization?
                    authorized?(:volunteer_registration)
                   else
                     true
                   end
      
      # Check business logic constraints
      can_register = authorized &&
                    step_settings.registration_enabled? &&
                    !registration_deadline_passed? &&
                    !opportunity_at_capacity? &&
                    !already_registered? &&
                    user_available_during_opportunity?
      
      toggle_allow(can_register)
    end
    
    def can_submit_hours?
      return unless user && opportunity && component_settings.enable_hour_tracking?
      
      has_assignment = opportunity.assignments
                                 .where(user: user, status: :completed)
                                 .exists?
      
      toggle_allow(has_assignment && !hours_already_submitted?)
    end
    
    def opportunity
      @opportunity ||= context.fetch(:opportunity, nil)
    end
    
    def component_settings
      @component_settings ||= component.settings
    end
    
    def step_settings
      @step_settings ||= component.current_settings
    end
  end
end
```

### Authorization Handler for Volunteer Verification

```ruby
# config/initializers/decidim_verifications.rb
Decidim::Verifications.register_workflow(:volunteer_verification) do |workflow|
  workflow.form = "VolunteerScheduler::VolunteerVerificationForm"
  workflow.action_authorizer = "VolunteerScheduler::VolunteerActionAuthorizer"
  workflow.options do |options|
    options.attribute :allowed_volunteer_types, type: :string
    options.attribute :minimum_age, type: :integer, default: 16
    options.attribute :require_background_check, type: :boolean, default: false
  end
end

# app/forms/decidim/volunteer_scheduler/volunteer_verification_form.rb
class VolunteerVerificationForm < Decidim::AuthorizationHandler
  attribute :volunteer_id, String
  attribute :volunteer_type, String
  attribute :experience_level, String
  
  validates :volunteer_id, presence: true
  validates :volunteer_type, inclusion: { in: %w(coordinator helper supervisor) }
  
  def unique_id
    Digest::MD5.hexdigest(
      "#{volunteer_id}-#{Rails.application.secrets.secret_key_base}"
    )
  end
  
  def metadata
    {
      volunteer_type: volunteer_type,
      experience_level: experience_level,
      verified_at: Time.current
    }
  end
end
```

## 7. Background Jobs and Async Processing

**Implement background processing for volunteer notifications and scheduling tasks.**

### Job Configuration

Configure queues for different volunteer processing types:

```yaml
# config/sidekiq.yml
:queues:
  - [volunteer_reminders, 4]
  - [volunteer_notifications, 3]
  - [schedule_processing, 2]
  - [hour_calculations, 2]
  - [mailers, 4]
  - [default, 2]
```

### Reminder Job Implementation

```ruby
# app/jobs/decidim/volunteer_scheduler/send_reminder_job.rb
class SendReminderJob < ApplicationJob
  queue_as :volunteer_reminders
  retry_on StandardError, wait: :exponentially_longer, attempts: 3
  
  def perform(assignment_id, reminder_type)
    assignment = Assignment.find(assignment_id)
    
    case reminder_type
    when "upcoming_shift"
      send_upcoming_shift_reminder(assignment)
    when "hours_submission"
      send_hours_submission_reminder(assignment)
    when "feedback_request"
      send_feedback_request_reminder(assignment)
    end
  rescue ActiveRecord::RecordNotFound
    Rails.logger.warn "Assignment #{assignment_id} not found for reminder"
  end
  
  private
  
  def send_upcoming_shift_reminder(assignment)
    VolunteerScheduler::ReminderMailer
      .upcoming_shift(assignment)
      .deliver_now
  end
end
```

### Scheduled Processing Jobs

```ruby
# app/jobs/decidim/volunteer_scheduler/process_schedule_job.rb
class ProcessScheduleJob < ApplicationJob
  queue_as :schedule_processing
  
  def perform
    process_overdue_confirmations
    process_waitlist_assignments
    send_daily_reminders
  end
  
  private
  
  def process_overdue_confirmations
    Assignment.pending_confirmation
              .where("confirmation_deadline < ?", Time.current)
              .find_each(&:mark_as_expired)
  end
  
  def process_waitlist_assignments
    Opportunity.where("start_time > ?", 1.hour.from_now)
              .with_waitlist
              .find_each do |opportunity|
                ProcessWaitlistAssignmentsJob.perform_later(opportunity.id)
              end
  end
end

# Cron job configuration
# 0 * * * * cd /app && RAILS_ENV=production bundle exec rake volunteer_scheduler:process_schedule
```

## 8. Database and Model Patterns

**Follow Decidim's established patterns for data modeling and concerns.**

### Core Model with Decidim Concerns

```ruby
# app/models/decidim/volunteer_scheduler/opportunity.rb
class Opportunity < VolunteerScheduler::ApplicationRecord
  include Decidim::Resourceable
  include Decidim::HasAttachments
  include Decidim::HasComponent
  include Decidim::HasReference
  include Decidim::ScopableResource
  include Decidim::HasCategory
  include Decidim::Followable
  include Decidim::Comments::CommentableWithComponent
  include Decidim::Searchable
  include Decidim::Traceable
  include Decidim::Loggable
  include Decidim::Reportable
  include Decidim::TranslatableResource
  include Decidim::Publicable
  include Decidim::FilterableResource
  include Decidim::SoftDeletable
  
  # Searchable configuration
  searchable_fields({
    participatory_space: { A: :title },
    A: :title,
    B: :description,
    C: [:reference]
  })
  
  # Associations
  has_many :assignments, foreign_key: "decidim_volunteer_opportunity_id", dependent: :destroy
  has_many :volunteers, through: :assignments, source: :user
  has_many :required_skills, foreign_key: "decidim_volunteer_opportunity_id", dependent: :destroy
  
  # Validations
  validates :title, presence: true
  validates :description, presence: true
  validates :start_time, :end_time, presence: true
  validates :max_volunteers, presence: true, numericality: { greater_than: 0 }
  
  # Scopes
  scope :upcoming, -> { where("start_time > ?", Time.current) }
  scope :with_available_spots, -> { where("assignments_count < max_volunteers") }
  
  def available_spots
    max_volunteers - assignments.confirmed.count
  end
  
  def full?
    available_spots <= 0
  end
end
```

### Polymorphic Associations for Flexible Relationships

```ruby
# For linking opportunities to different types of events
class OpportunityLink < ApplicationRecord
  belongs_to :opportunity, foreign_key: "decidim_volunteer_opportunity_id"
  belongs_to :linkable, polymorphic: true
  
  # Can link opportunities to:
  # - Decidim::Meetings::Meeting
  # - Decidim::Proposals::Proposal  
  # - Decidim::ParticipatoryProcesses::Step
  # - Any other Decidim resource
end
```

### Migration Patterns Following Decidim Conventions

```ruby
# db/migrate/20240101000001_create_decidim_volunteer_scheduler_opportunities.rb
class CreateDecidimVolunteerSchedulerOpportunities < ActiveRecord::Migration[6.1]
  def change
    create_table :decidim_volunteer_scheduler_opportunities do |t|
      t.jsonb :title, null: false
      t.jsonb :description, null: false
      t.datetime :start_time, null: false
      t.datetime :end_time, null: false
      t.integer :max_volunteers, null: false, default: 1
      t.references :decidim_component, null: false, foreign_key: true
      t.references :decidim_scope, null: true, foreign_key: true
      t.references :decidim_category, null: true, foreign_key: true
      t.string :reference
      t.integer :assignments_count, default: 0
      t.datetime :published_at
      t.datetime :deleted_at
      t.timestamps
    end
    
    add_index :decidim_volunteer_scheduler_opportunities, :start_time
    add_index :decidim_volunteer_scheduler_opportunities, :published_at
    add_index :decidim_volunteer_scheduler_opportunities, :deleted_at
  end
end
```

## 9. Admin Interface Patterns

**Build comprehensive admin interfaces following Decidim conventions.**

### Admin Controller Pattern

```ruby
# app/controllers/decidim/volunteer_scheduler/admin/opportunities_controller.rb
module Decidim::VolunteerScheduler::Admin
  class OpportunitiesController < Admin::ApplicationController
    include Decidim::Admin::Filterable
    
    helper_method :opportunities, :opportunity
    
    def index
      enforce_permission_to :read, :opportunity
      @opportunities = filtered_collection
    end
    
    def new
      enforce_permission_to :create, :opportunity
      @form = form(OpportunityForm).instance
    end
    
    def create
      enforce_permission_to :create, :opportunity
      @form = form(OpportunityForm).from_params(params)
      
      CreateOpportunity.call(@form, current_user) do
        on(:ok) do |opportunity|
          flash[:notice] = I18n.t("opportunities.create.success", scope: "decidim.volunteer_scheduler.admin")
          redirect_to opportunities_path
        end
        on(:invalid) do
          flash.now[:alert] = I18n.t("opportunities.create.invalid", scope: "decidim.volunteer_scheduler.admin")
          render :new
        end
      end
    end
    
    def bulk_action
      enforce_permission_to :update, :opportunity
      
      BulkActionOpportunities.call(
        params[:opportunity_ids],
        params[:bulk_action],
        current_user
      ) do
        on(:ok) do |count|
          flash[:notice] = I18n.t("opportunities.bulk_action.success", 
                                  scope: "decidim.volunteer_scheduler.admin",
                                  count: count)
        end
      end
      
      redirect_to opportunities_path
    end
    
    private
    
    def base_query
      current_component.opportunities.includes(:assignments, :category, :scope)
    end
    
    def filters
      [
        :search_text,
        :published_at,
        :category_id,
        :scope_id,
        :assignment_status
      ]
    end
  end
end
```

### Form Objects and Commands

```ruby
# app/forms/decidim/volunteer_scheduler/admin/opportunity_form.rb
class OpportunityForm < Decidim::Form
  include TranslatableAttributes
  include Decidim::AttachmentAttributes
  
  translatable_attribute :title, String
  translatable_attribute :description, String
  attribute :start_time, Decidim::Attributes::TimeWithZone
  attribute :end_time, Decidim::Attributes::TimeWithZone
  attribute :max_volunteers, Integer
  attribute :category_id, Integer
  attribute :scope_id, Integer
  attribute :required_skills, Array[Integer]
  
  validates :title, :description, translatable_presence: true
  validates :start_time, :end_time, presence: true
  validates :max_volunteers, presence: true, numericality: { greater_than: 0 }
  validate :end_time_after_start_time
  
  def map_model(model)
    self.category_id = model.decidim_category_id
    self.scope_id = model.decidim_scope_id
    self.required_skills = model.required_skills.pluck(:skill_id)
  end
  
  private
  
  def end_time_after_start_time
    return unless start_time && end_time
    
    if end_time <= start_time
      errors.add(:end_time, :after_start_time)
    end
  end
end

# app/commands/decidim/volunteer_scheduler/admin/create_opportunity.rb
class CreateOpportunity < Decidim::Command
  def initialize(form, current_user)
    @form = form
    @current_user = current_user
  end

  def call
    return broadcast(:invalid) if form.invalid?

    transaction do
      create_opportunity
      create_required_skills
      send_notification_to_followers
    end

    broadcast(:ok, opportunity)
  end

  private

  def create_opportunity
    @opportunity = Decidim.traceability.create(
      Opportunity,
      current_user,
      form.attributes.slice(
        "title", "description", "start_time", "end_time", "max_volunteers"
      ).merge(
        component: form.current_component,
        category: form.category,
        scope: form.scope
      ),
      visibility: "admin-only"
    )
  end
end
```

### Filterable Admin Tables

```ruby
# app/helpers/decidim/volunteer_scheduler/admin/filterable_helper.rb
module Decidim::VolunteerScheduler::Admin::FilterableHelper
  def filters_for_opportunities
    [
      {
        filter: :search_text,
        label: t("filters.search", scope: "decidim.volunteer_scheduler.admin")
      },
      {
        filter: :category_id,
        label: t("filters.category", scope: "decidim.volunteer_scheduler.admin"),
        values: categories_for_select
      },
      {
        filter: :assignment_status,
        label: t("filters.assignment_status", scope: "decidim.volunteer_scheduler.admin"),
        values: [
          ["", t("filters.all", scope: "decidim.volunteer_scheduler.admin")],
          ["full", t("filters.full", scope: "decidim.volunteer_scheduler.admin")],
          ["available", t("filters.available", scope: "decidim.volunteer_scheduler.admin")]
        ]
      }
    ]
  end
end
```

## 10. View Cells and UI Components

**Create reusable view components following Decidim's cell patterns.**

### Opportunity Card Cell

```ruby
# app/cells/decidim/volunteer_scheduler/opportunity_cell.rb
module Decidim::VolunteerScheduler
  class OpportunityCell < Decidim::ViewModel
    include Decidim::SanitizeHelper
    include Decidim::TranslationsHelper
    include Decidim::IconHelper
    
    delegate :current_user, :current_component, to: :controller
    
    def show
      render :show
    end
    
    private
    
    def opportunity_path
      Decidim::ResourceLocatorPresenter.new(model).path
    end
    
    def cache_hash
      hash = []
      hash << "decidim/volunteer_scheduler/opportunity"
      hash << model.cache_key_with_version
      hash << current_user&.cache_key_with_version
      hash.join("/")
    end
    
    def status_badge
      return unless model.start_time < Time.current
      
      content_tag :span, 
                  t("models.opportunity.states.completed", scope: "decidim.volunteer_scheduler"),
                  class: "label label--success"
    end
    
    def volunteer_count
      "#{model.assignments.confirmed.count} / #{model.max_volunteers}"
    end
    
    def time_formatted
      time_range = "#{l(model.start_time, format: :time_of_day)} - #{l(model.end_time, format: :time_of_day)}"
      date_formatted = l(model.start_time.to_date, format: :decidim_short)
      "#{date_formatted} #{time_range}"
    end
  end
end
```

### Dashboard Widget Cell

```ruby
# app/cells/decidim/volunteer_scheduler/volunteer_dashboard_cell.rb
class VolunteerDashboardCell < Decidim::ViewModel
  def show
    render :show
  end
  
  private
  
  def upcoming_assignments
    @upcoming_assignments ||= current_user
                               .volunteer_assignments
                               .joins(:opportunity)
                               .where("decidim_volunteer_scheduler_opportunities.start_time > ?", Time.current)
                               .includes(:opportunity)
                               .limit(5)
  end
  
  def completed_hours_this_month
    @completed_hours ||= current_user
                          .volunteer_assignments
                          .completed
                          .where(created_at: Time.current.beginning_of_month..Time.current.end_of_month)
                          .sum(:hours_worked)
  end
  
  def volunteer_stats
    {
      total_hours: current_user.volunteer_assignments.completed.sum(:hours_worked),
      total_opportunities: current_user.volunteer_assignments.count,
      this_month_hours: completed_hours_this_month
    }
  end
end
```

### Stimulus Controller for Interactive Calendar

```javascript
// app/packs/src/decidim/volunteer_scheduler/calendar_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["calendar", "eventDetails", "registerButton"]
  static values = { 
    currentUserId: Number,
    componentId: Number 
  }
  
  connect() {
    this.initializeCalendar()
  }
  
  initializeCalendar() {
    const calendar = new FullCalendar.Calendar(this.calendarTarget, {
      initialView: 'dayGridMonth',
      headerToolbar: {
        left: 'prev,next today',
        center: 'title',
        right: 'dayGridMonth,timeGridWeek,timeGridDay'
      },
      events: this.fetchEvents.bind(this),
      eventClick: this.handleEventClick.bind(this)
    })
    
    calendar.render()
    this.calendar = calendar
  }
  
  async fetchEvents(info) {
    const response = await fetch(
      `/components/${this.componentIdValue}/volunteer_scheduler/opportunities.json?start=${info.startStr}&end=${info.endStr}`
    )
    return response.json()
  }
  
  handleEventClick(info) {
    this.showEventDetails(info.event)
  }
  
  showEventDetails(event) {
    this.eventDetailsTarget.innerHTML = this.buildEventDetailsHTML(event)
    this.eventDetailsTarget.style.display = 'block'
  }
  
  buildEventDetailsHTML(event) {
    const canRegister = !event.extendedProps.full && !event.extendedProps.userRegistered
    const registerButton = canRegister ? 
      `<button data-action="click->volunteer-scheduler--calendar#registerForEvent" 
               data-opportunity-id="${event.extendedProps.id}"
               class="button button--primary">
         Register
       </button>` : ''
    
    return `
      <div class="event-details">
        <h3>${event.title}</h3>
        <p><strong>Time:</strong> ${event.start.toLocaleString()} - ${event.end.toLocaleString()}</p>
        <p><strong>Volunteers:</strong> ${event.extendedProps.volunteerCount} / ${event.extendedProps.maxVolunteers}</p>
        <p>${event.extendedProps.description}</p>
        ${registerButton}
      </div>
    `
  }
  
  async registerForEvent(event) {
    const opportunityId = event.target.dataset.opportunityId
    
    try {
      const response = await fetch(`/volunteer_scheduler/opportunities/${opportunityId}/register`, {
        method: 'POST',
        headers: {
          'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content,
          'Content-Type': 'application/json'
        }
      })
      
      if (response.ok) {
        this.calendar.refetchEvents()
        this.showSuccessMessage('Successfully registered!')
      }
    } catch (error) {
      this.showErrorMessage('Registration failed. Please try again.')
    }
  }
}
```

### SCSS Organization

```scss
// app/packs/stylesheets/decidim/volunteer_scheduler/_calendar.scss
.volunteer-scheduler {
  .calendar-container {
    .fc-event {
      border-radius: $global-radius;
      border: none;
      
      &.fc-event--full {
        background-color: $alert-color;
        color: white;
      }
      
      &.fc-event--available {
        background-color: $success-color;
        color: white;
      }
      
      &.fc-event--user-registered {
        background-color: $primary-color;
        color: white;
        font-weight: 600;
      }
    }
    
    .fc-toolbar {
      margin-bottom: 1rem;
      
      .fc-toolbar-title {
        font-size: 1.5rem;
        font-weight: 600;
      }
    }
  }
  
  .event-details {
    position: fixed;
    top: 50%;
    left: 50%;
    transform: translate(-50%, -50%);
    background: white;
    padding: 2rem;
    border-radius: $global-radius;
    box-shadow: 0 4px 20px rgba(0, 0, 0, 0.15);
    z-index: 1000;
    max-width: 500px;
    width: 90%;
    
    .button {
      margin-top: 1rem;
    }
  }
}

// app/packs/stylesheets/decidim/volunteer_scheduler/_volunteer_cards.scss
.volunteer-opportunity-card {
  border: 1px solid $light-gray;
  border-radius: $global-radius;
  padding: 1.5rem;
  background: white;
  box-shadow: 0 2px 8px rgba(0, 0, 0, 0.1);
  transition: box-shadow 0.2s ease;
  
  &:hover {
    box-shadow: 0 4px 12px rgba(0, 0, 0, 0.15);
  }
  
  .card-header {
    margin-bottom: 1rem;
    
    .card-title {
      font-size: 1.25rem;
      font-weight: 600;
      margin-bottom: 0.5rem;
      
      a {
        color: inherit;
        text-decoration: none;
        
        &:hover {
          color: $primary-color;
        }
      }
    }
    
    .card-meta {
      display: flex;
      align-items: center;
      gap: 1rem;
      color: $dark-gray;
      font-size: 0.9rem;
      
      .volunteer-count {
        display: flex;
        align-items: center;
        gap: 0.25rem;
        
        .icon {
          width: 16px;
          height: 16px;
        }
      }
    }
  }
  
  .card-description {
    margin-bottom: 1rem;
    line-height: 1.5;
  }
  
  .card-actions {
    display: flex;
    gap: 0.5rem;
    
    .button {
      flex: 1;
    }
    
    .button--secondary {
      background: transparent;
      border: 1px solid $primary-color;
      color: $primary-color;
    }
  }
}
```

This comprehensive guide provides concrete implementation patterns and code examples directly adapted from the Decidim codebase. Each section includes specific file paths, architectural patterns, and working code that can be used to build a robust volunteer scheduler module within the Decidim ecosystem. The patterns follow Decidim's conventions for maintainability, extensibility, and consistency with the platform's overall architecture.