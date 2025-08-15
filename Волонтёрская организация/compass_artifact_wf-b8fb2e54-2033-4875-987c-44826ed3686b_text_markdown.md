# Decidim Module Development Guide: Production-Ready Volunteer Scheduler Implementation

This comprehensive research provides concrete patterns, code examples, and architectural decisions for upgrading the decidim-volunteer_scheduler component to Phase 1 production quality, based on analysis of official Decidim documentation and successful production modules.

## Core Architecture Framework

### Component Structure and Generation

**Standard Module Structure:**
```
decidim-volunteer_scheduler/
├── app/
│   ├── cells/decidim/volunteer_scheduler/     # UI components
│   ├── commands/decidim/volunteer_scheduler/  # Business logic
│   ├── controllers/                          # Request handling
│   ├── forms/                               # Validation objects
│   ├── models/                              # ActiveRecord models
│   ├── permissions/                         # Authorization logic
│   ├── queries/                             # Complex data retrieval
│   └── services/                            # Business logic services
├── config/locales/                          # I18n translations
├── db/migrate/                              # Database migrations
└── lib/decidim/volunteer_scheduler/
    ├── admin_engine.rb                      # Admin interface
    ├── component.rb                         # Component manifest
    └── engine.rb                            # Main Rails engine
```

**Component Manifest Registration:**
```ruby
# lib/decidim/volunteer_scheduler/component.rb
Decidim.register_component(:volunteer_scheduler) do |component|
  component.engine = Decidim::VolunteerScheduler::Engine
  component.admin_engine = Decidim::VolunteerScheduler::AdminEngine
  component.icon = "decidim/volunteer_scheduler/icon.svg"
  component.permissions_class_name = "Decidim::VolunteerScheduler::Permissions"

  # Resource registration for searchability
  component.register_resource(:volunteer_shift) do |resource|
    resource.model_class_name = "Decidim::VolunteerScheduler::VolunteerShift"
    resource.card = "decidim/volunteer_scheduler/volunteer_shift"
    resource.searchable = true
  end

  # Global settings
  component.settings(:global) do |settings|
    settings.attribute :max_volunteers_per_shift, type: :integer, default: 10
    settings.attribute :enable_shift_reminders, type: :boolean, default: true
    settings.attribute :xp_points_per_hour, type: :integer, default: 10
    settings.attribute :enable_referral_system, type: :boolean, default: false
  end

  # Step-specific settings
  component.settings(:step) do |settings|
    settings.attribute :volunteer_signup_enabled, type: :boolean, default: true
    settings.attribute :require_verification, type: :boolean, default: false
  end
end
```

## Database Schema and Migration Patterns

### Core Entity Models

**Volunteer Shifts Table:**
```ruby
class CreateDecidimVolunteerSchedulerShifts < ActiveRecord::Migration[7.0]
  def change
    create_table :decidim_volunteer_scheduler_shifts do |t|
      t.jsonb :title, null: false
      t.jsonb :description
      t.datetime :start_time, null: false
      t.datetime :end_time, null: false
      t.integer :max_volunteers, null: false, default: 1
      t.integer :xp_points_per_hour, default: 0
      t.references :decidim_component, null: false, index: true
      t.references :decidim_category, null: true, index: true
      t.references :decidim_author, null: false, index: true
      t.integer :volunteer_assignments_count, default: 0
      t.datetime :published_at
      t.integer :reference, null: false
      t.timestamps

      # Performance indexes
      t.index :published_at
      t.index [:decidim_component_id, :published_at]
      t.index [:start_time, :end_time]
    end

    add_foreign_key :decidim_volunteer_scheduler_shifts, :decidim_components
    add_foreign_key :decidim_volunteer_scheduler_shifts, :decidim_categories
    add_foreign_key :decidim_volunteer_scheduler_shifts, :decidim_users, column: :decidim_author_id
  end
end
```

**Volunteer Assignments Table:**
```ruby
class CreateDecidimVolunteerSchedulerAssignments < ActiveRecord::Migration[7.0]
  def change
    create_table :decidim_volunteer_scheduler_assignments do |t|
      t.references :decidim_volunteer_scheduler_shift, null: false, index: { name: 'idx_assignments_on_shift' }
      t.references :decidim_user, null: false, index: true
      t.datetime :signed_up_at
      t.datetime :checked_in_at
      t.datetime :checked_out_at
      t.integer :xp_earned, default: 0
      t.text :notes
      t.integer :status, default: 0 # enrolled, confirmed, completed, cancelled
      t.timestamps

      # Prevent duplicate assignments
      t.index [:decidim_volunteer_scheduler_shift_id, :decidim_user_id], 
              unique: true, name: 'idx_unique_volunteer_assignment'
    end
  end
end
```

**Volunteer Profiles Extension:**
```ruby
class CreateDecidimVolunteerSchedulerProfiles < ActiveRecord::Migration[7.0]
  def change
    create_table :decidim_volunteer_scheduler_profiles do |t|
      t.references :decidim_user, null: false, index: true
      t.jsonb :skills, default: []
      t.jsonb :availability_preferences, default: {}
      t.integer :total_xp_points, default: 0
      t.integer :total_hours_volunteered, default: 0
      t.string :volunteer_level, default: 'newcomer'
      t.references :referred_by, null: true, foreign_key: { to_table: :decidim_users }
      t.string :referral_code, index: { unique: true }
      t.timestamps
    end

    add_foreign_key :decidim_volunteer_scheduler_profiles, :decidim_users
  end
end
```

## Model Implementation with Decidim Patterns

### Core Model with Decidim Concerns

**VolunteerShift Model:**
```ruby
module Decidim
  module VolunteerScheduler
    class VolunteerShift < Decidim::ApplicationRecord
      include Decidim::Resourceable
      include Decidim::Traceable
      include Decidim::Loggable
      include Decidim::Followable
      include Decidim::TranslatableResource
      include Decidim::Searchable

      self.table_name = "decidim_volunteer_scheduler_shifts"

      translatable_fields :title, :description

      belongs_to :component, foreign_key: "decidim_component_id", class_name: "Decidim::Component"
      belongs_to :category, foreign_key: "decidim_category_id", class_name: "Decidim::Category", optional: true
      belongs_to :author, foreign_key: "decidim_author_id", class_name: "Decidim::User"
      has_many :volunteer_assignments, dependent: :destroy
      has_many :volunteers, through: :volunteer_assignments, source: :user

      validates :title, :description, :start_time, :end_time, presence: true
      validates :max_volunteers, presence: true, numericality: { greater_than: 0 }
      validate :end_time_after_start_time
      validate :future_start_time, on: :create

      scope :published, -> { where.not(published_at: nil) }
      scope :upcoming, -> { where("start_time > ?", Time.current) }
      scope :available_for_signup, -> { published.upcoming.joins(:volunteer_assignments).group(:id).having("COUNT(volunteer_assignments.id) < max_volunteers") }

      searchable_fields({
        scope_id: :decidim_scope_id,
        participatory_space: { component: :participatory_space },
        A: :title,
        D: :description,
        datetime: :published_at
      }, index_on_create: ->(shift) { shift.published? })

      def self.log_presenter_class_for(_log)
        Decidim::VolunteerScheduler::AdminLog::VolunteerShiftPresenter
      end

      def published?
        published_at.present?
      end

      def can_be_volunteered_by?(user)
        return false unless published? && upcoming?
        return false unless user&.confirmed?
        return false if volunteer_assignments.exists?(user: user)
        
        volunteer_assignments.count < max_volunteers
      end

      def duration_hours
        return 0 unless start_time && end_time
        
        ((end_time - start_time) / 1.hour).round(2)
      end

      def total_xp_points
        duration_hours * (xp_points_per_hour || component.settings.xp_points_per_hour)
      end

      private

      def end_time_after_start_time
        return unless start_time && end_time
        
        errors.add(:end_time, :invalid) if end_time <= start_time
      end

      def future_start_time
        return unless start_time
        
        errors.add(:start_time, :invalid) if start_time <= Time.current
      end
    end
  end
end
```

**VolunteerProfile Model with Gamification:**
```ruby
module Decidim
  module VolunteerScheduler
    class VolunteerProfile < Decidim::ApplicationRecord
      self.table_name = "decidim_volunteer_scheduler_profiles"

      belongs_to :user, foreign_key: "decidim_user_id", class_name: "Decidim::User"
      belongs_to :referred_by, class_name: "Decidim::User", optional: true
      has_many :referrals, class_name: "Decidim::VolunteerScheduler::VolunteerProfile", foreign_key: "referred_by_id"

      VOLUNTEER_LEVELS = %w[newcomer contributor champion ambassador legend].freeze

      validates :volunteer_level, inclusion: { in: VOLUNTEER_LEVELS }
      validates :referral_code, presence: true, uniqueness: true

      before_create :generate_referral_code

      def calculate_level
        case total_xp_points
        when 0...100 then 'newcomer'
        when 100...500 then 'contributor'
        when 500...1500 then 'champion'
        when 1500...5000 then 'ambassador'
        else 'legend'
        end
      end

      def update_xp_and_level!(additional_xp)
        increment!(:total_xp_points, additional_xp)
        update!(volunteer_level: calculate_level)
      end

      def referral_commission_rate(level = 1)
        case level
        when 1 then 0.15  # 15% for direct referrals
        when 2 then 0.08  # 8% for second level
        when 3 then 0.05  # 5% for third level
        when 4 then 0.02  # 2% for fourth level
        when 5 then 0.01  # 1% for fifth level
        else 0
        end
      end

      private

      def generate_referral_code
        self.referral_code = SecureRandom.alphanumeric(8).upcase
      end
    end
  end
end
```

## Command and Form Pattern Implementation

### Form Objects with Validation

**VolunteerShift Form:**
```ruby
module Decidim
  module VolunteerScheduler
    module Admin
      class VolunteerShiftForm < Decidim::Form
        include Decidim::TranslatableAttributes
        include Decidim::AttachmentAttributes

        translatable_attribute :title, String
        translatable_attribute :description, String
        
        attribute :start_time, Decidim::Attributes::TimeWithZone
        attribute :end_time, Decidim::Attributes::TimeWithZone
        attribute :max_volunteers, Integer
        attribute :xp_points_per_hour, Integer
        attribute :decidim_category_id, Integer
        
        validates :title, :description, :start_time, :end_time, presence: true
        validates :max_volunteers, presence: true, numericality: { greater_than: 0, less_than: 100 }
        validates :xp_points_per_hour, presence: true, numericality: { greater_than_or_equal_to: 0 }
        validate :end_time_after_start_time
        validate :future_start_time
        validate :category_belongs_to_organization

        def map_model(model)
          self.decidim_category_id = model.category&.id
        end

        private

        def end_time_after_start_time
          return unless start_time && end_time
          errors.add(:end_time, :invalid) if end_time <= start_time
        end

        def future_start_time
          return unless start_time
          errors.add(:start_time, :invalid) if start_time <= 1.hour.from_now
        end

        def category_belongs_to_organization
          return unless decidim_category_id.present?
          
          category = current_organization.categories.find_by(id: decidim_category_id)
          errors.add(:decidim_category_id, :invalid) unless category
        end
      end
    end
  end
end
```

### Command Objects for Business Logic

**CreateVolunteerShift Command:**
```ruby
module Decidim
  module VolunteerScheduler
    module Admin
      class CreateVolunteerShift < Decidim::Command
        def initialize(form, current_user)
          @form = form
          @current_user = current_user
        end

        def call
          return broadcast(:invalid) if form.invalid?

          transaction do
            create_volunteer_shift
            create_attachment if process_attachments?
            send_notification_to_followers
            log_action
          end

          broadcast(:ok, volunteer_shift)
        end

        private

        attr_reader :form, :current_user, :volunteer_shift

        def create_volunteer_shift
          @volunteer_shift = Decidim.traceability.create!(
            VolunteerShift,
            current_user,
            form.attributes.slice(
              :title, :description, :start_time, :end_time, 
              :max_volunteers, :xp_points_per_hour
            ).merge(
              component: form.current_component,
              category: category,
              author: current_user
            ),
            visibility: "all"
          )
        end

        def category
          return unless form.decidim_category_id.present?
          
          form.current_organization.categories.find(form.decidim_category_id)
        end

        def send_notification_to_followers
          return unless volunteer_shift.published?

          Decidim::EventsManager.publish(
            event: "decidim.events.volunteer_scheduler.volunteer_shift_created",
            event_class: Decidim::VolunteerScheduler::VolunteerShiftCreatedEvent,
            resource: volunteer_shift,
            affected_users: [current_user],
            followers: volunteer_shift.component.followers
          )
        end

        def log_action
          Decidim.loggability.log_action(
            "create",
            volunteer_shift,
            current_user,
            "New volunteer shift created"
          )
        end
      end
    end
  end
end
```

**VolunteerForShift Command with XP Integration:**
```ruby
module Decidim
  module VolunteerScheduler
    class VolunteerForShift < Decidim::Command
      def initialize(volunteer_shift, current_user)
        @volunteer_shift = volunteer_shift
        @current_user = current_user
      end

      def call
        return broadcast(:invalid) unless can_volunteer?

        transaction do
          create_assignment
          process_referral_points
          send_confirmation_notification
          log_action
        end

        broadcast(:ok, assignment)
      end

      private

      attr_reader :volunteer_shift, :current_user, :assignment

      def can_volunteer?
        volunteer_shift.can_be_volunteered_by?(current_user)
      end

      def create_assignment
        @assignment = VolunteerAssignment.create!(
          volunteer_shift: volunteer_shift,
          user: current_user,
          signed_up_at: Time.current,
          status: :enrolled
        )
      end

      def process_referral_points
        return unless volunteer_shift.component.settings.enable_referral_system

        referral_service = ReferralProcessingService.new(current_user)
        referral_service.process_volunteer_signup(volunteer_shift.total_xp_points)
      end

      def send_confirmation_notification
        Decidim::EventsManager.publish(
          event: "decidim.events.volunteer_scheduler.volunteer_signed_up",
          event_class: Decidim::VolunteerScheduler::VolunteerSignedUpEvent,
          resource: volunteer_shift,
          affected_users: [current_user, volunteer_shift.author]
        )
      end

      def log_action
        Decidim.loggability.log_action(
          "volunteer_signup",
          volunteer_shift,
          current_user,
          "User signed up for volunteer shift"
        )
      end
    end
  end
end
```

## Service Objects for Business Logic

### Referral Processing Service

```ruby
module Decidim
  module VolunteerScheduler
    class ReferralProcessingService
      def initialize(user)
        @user = user
        @profile = find_or_create_profile
      end

      def process_volunteer_signup(base_xp_points)
        return unless profile.referred_by.present?

        process_referral_chain(profile.referred_by, base_xp_points, 1)
      end

      def process_shift_completion(completed_xp_points)
        profile.update_xp_and_level!(completed_xp_points)
        
        return unless profile.referred_by.present?

        process_referral_chain(profile.referred_by, completed_xp_points, 1)
      end

      private

      attr_reader :user, :profile

      def find_or_create_profile
        VolunteerProfile.find_or_create_by(user: user)
      end

      def process_referral_chain(referrer, base_points, level)
        return if level > 5 # Max 5 levels deep

        referrer_profile = VolunteerProfile.find_by(user: referrer)
        return unless referrer_profile

        commission_rate = referrer_profile.referral_commission_rate(level)
        commission_points = (base_points * commission_rate).round

        if commission_points > 0
          referrer_profile.update_xp_and_level!(commission_points)
          
          # Create referral earning record for transparency
          ReferralEarning.create!(
            referrer: referrer,
            referred_user: user,
            xp_earned: commission_points,
            level: level,
            source_activity: 'volunteer_completion'
          )
        end

        # Continue up the referral chain
        if referrer_profile.referred_by.present?
          process_referral_chain(referrer_profile.referred_by, base_points, level + 1)
        end
      end
    end
  end
end
```

### Volunteer Dashboard Service

```ruby
module Decidim
  module VolunteerScheduler
    class VolunteerDashboardService
      def initialize(user, component)
        @user = user
        @component = component
        @profile = VolunteerProfile.find_by(user: user)
      end

      def dashboard_data
        {
          profile_stats: profile_statistics,
          upcoming_shifts: upcoming_volunteer_shifts,
          recent_activity: recent_volunteer_activity,
          referral_stats: referral_statistics,
          available_shifts: available_shifts_for_signup
        }
      end

      private

      attr_reader :user, :component, :profile

      def profile_statistics
        return default_stats unless profile

        {
          total_xp: profile.total_xp_points,
          volunteer_level: profile.volunteer_level,
          hours_volunteered: profile.total_hours_volunteered,
          shifts_completed: completed_assignments.count,
          referrals_count: profile.referrals.count
        }
      end

      def upcoming_volunteer_shifts
        VolunteerAssignment
          .joins(:volunteer_shift)
          .where(user: user, volunteer_shift: { component: component })
          .where("volunteer_shifts.start_time > ?", Time.current)
          .includes(:volunteer_shift)
          .order("volunteer_shifts.start_time ASC")
          .limit(5)
      end

      def recent_volunteer_activity
        VolunteerAssignment
          .joins(:volunteer_shift)
          .where(user: user, volunteer_shift: { component: component })
          .where("volunteer_assignments.updated_at > ?", 30.days.ago)
          .includes(:volunteer_shift)
          .order("volunteer_assignments.updated_at DESC")
          .limit(10)
      end

      def referral_statistics
        return {} unless profile&.referral_code

        {
          referral_code: profile.referral_code,
          direct_referrals: profile.referrals.count,
          total_referral_earnings: calculate_total_referral_earnings
        }
      end

      def available_shifts_for_signup
        VolunteerShift
          .where(component: component)
          .available_for_signup
          .where.not(id: user_shift_ids)
          .limit(10)
      end

      def completed_assignments
        @completed_assignments ||= VolunteerAssignment
          .joins(:volunteer_shift)
          .where(user: user, volunteer_shift: { component: component }, status: :completed)
      end

      def user_shift_ids
        @user_shift_ids ||= VolunteerAssignment
          .joins(:volunteer_shift)
          .where(user: user, volunteer_shift: { component: component })
          .pluck(:decidim_volunteer_scheduler_shift_id)
      end

      def calculate_total_referral_earnings
        return 0 unless profile

        ReferralEarning.where(referrer: user).sum(:xp_earned)
      end

      def default_stats
        {
          total_xp: 0,
          volunteer_level: 'newcomer',
          hours_volunteered: 0,
          shifts_completed: 0,
          referrals_count: 0
        }
      end
    end
  end
end
```

## Cell-Based View Components

### VolunteerShift Card Cell

```ruby
module Decidim
  module VolunteerScheduler
    class VolunteerShiftCell < Decidim::ViewModel
      include Cell::ViewModel::Partial
      include Decidim::ApplicationHelper
      include Decidim::Core::Engine.routes.url_helpers
      include ActionView::Helpers::DateHelper

      property :id
      property :title
      property :description
      property :start_time
      property :end_time
      property :max_volunteers
      property :volunteer_assignments_count

      def show
        render
      end

      def title_text
        translated_attribute(title)
      end

      def description_text
        truncate(translated_attribute(description), length: 150)
      end

      def time_display
        "#{l(start_time, format: :short)} - #{l(end_time, format: :short)}"
      end

      def volunteer_spots_display
        "#{volunteer_assignments_count}/#{max_volunteers} volunteers"
      end

      def spots_available?
        volunteer_assignments_count < max_volunteers
      end

      def can_volunteer?
        return false unless current_user
        return false unless spots_available?
        return false unless model.published?
        return false if model.start_time <= Time.current

        !already_volunteered?
      end

      def volunteer_button
        return unless can_volunteer?

        link_to t("decidim.volunteer_scheduler.volunteer_shifts.volunteer"),
                volunteer_path,
                method: :post,
                class: "button expanded",
                data: { confirm: t("decidim.volunteer_scheduler.volunteer_shifts.volunteer_confirm") }
      end

      def duration_display
        distance_of_time_in_words(start_time, end_time)
      end

      def xp_points_display
        return unless model.total_xp_points > 0

        content_tag :span, class: "label success" do
          "#{model.total_xp_points} XP"
        end
      end

      private

      def current_user
        context[:current_user]
      end

      def already_volunteered?
        return false unless current_user

        model.volunteer_assignments.exists?(user: current_user)
      end

      def volunteer_path
        decidim_volunteer_scheduler.volunteer_shift_path(model)
      end
    end
  end
end
```

### Volunteer Dashboard Cell

```ruby
module Decidim
  module VolunteerScheduler
    class VolunteerDashboardCell < Decidim::ViewModel
      include Decidim::ApplicationHelper

      def show
        render
      end

      private

      def dashboard_service
        @dashboard_service ||= VolunteerDashboardService.new(current_user, current_component)
      end

      def dashboard_data
        @dashboard_data ||= dashboard_service.dashboard_data
      end

      def profile_stats
        dashboard_data[:profile_stats]
      end

      def upcoming_shifts
        dashboard_data[:upcoming_shifts]
      end

      def referral_stats
        dashboard_data[:referral_stats]
      end

      def level_badge_class
        case profile_stats[:volunteer_level]
        when 'newcomer' then 'secondary'
        when 'contributor' then 'primary' 
        when 'champion' then 'success'
        when 'ambassador' then 'warning'
        when 'legend' then 'alert'
        end
      end

      def current_user
        context[:current_user]
      end

      def current_component
        context[:current_component]
      end
    end
  end
end
```

## Permission and Authorization System

### Comprehensive Permission Class

```ruby
module Decidim
  module VolunteerScheduler
    class Permissions < Decidim::DefaultPermissions
      def permissions
        return permission_action unless user

        case permission_action.scope
        when :public
          public_permissions
        when :admin
          admin_permissions
        end

        permission_action
      end

      private

      def public_permissions
        case permission_action.subject
        when :volunteer_shift
          case permission_action.action
          when :create
            create_volunteer_shift_permission
          when :read
            read_volunteer_shift_permission
          when :volunteer
            volunteer_for_shift_permission
          when :unvolunteer
            unvolunteer_from_shift_permission
          end
        when :volunteer_profile
          case permission_action.action
          when :read
            read_profile_permission
          when :update
            update_profile_permission
          end
        end
      end

      def admin_permissions
        return unless user.admin? || has_manageable_participatory_spaces?

        case permission_action.subject
        when :volunteer_shift
          case permission_action.action
          when :create, :update, :destroy, :publish, :unpublish
            toggle_allow(can_manage_component?)
          end
        when :component
          case permission_action.action
          when :read
            toggle_allow(can_read_admin_dashboard?)
          end
        end
      end

      def create_volunteer_shift_permission
        return unless component_settings.creation_enabled_for_users?

        toggle_allow(user&.confirmed? && can_participate_in_space?)
      end

      def read_volunteer_shift_permission
        case volunteer_shift
        when nil
          allow!
        else
          toggle_allow(can_read_volunteer_shift?)
        end
      end

      def volunteer_for_shift_permission
        return unless volunteer_shift&.published?
        return unless user&.confirmed?

        toggle_allow(
          volunteer_shift.can_be_volunteered_by?(user) &&
          can_participate_in_space? &&
          meets_verification_requirements?
        )
      end

      def unvolunteer_from_shift_permission
        return unless volunteer_shift&.published?
        return unless user&.confirmed?

        toggle_allow(
          volunteer_shift.volunteer_assignments.exists?(user: user) &&
          volunteer_shift.start_time > 24.hours.from_now
        )
      end

      def read_profile_permission
        return toggle_allow(true) if profile_user == user
        return toggle_allow(true) if user&.admin?

        toggle_allow(profile_user&.public_profile?)
      end

      def update_profile_permission
        toggle_allow(profile_user == user)
      end

      def can_read_volunteer_shift?
        return true if volunteer_shift.published?
        return true if user&.admin?
        return true if user == volunteer_shift.author

        false
      end

      def can_manage_component?
        return true if user&.admin?
        return true if user&.user_manager?

        component.participatory_space.can_be_managed_by?(user)
      end

      def can_read_admin_dashboard?
        return true if user&.admin?

        has_manageable_participatory_spaces?
      end

      def meets_verification_requirements?
        return true unless component_settings.require_verification?

        user.authorizations
            .where(name: component_settings.required_verification_handler)
            .where("granted_at IS NOT NULL")
            .exists?
      end

      def can_participate_in_space?
        component.participatory_space.can_participate?(user)
      end

      def has_manageable_participatory_spaces?
        return unless user

        user.user_roles.any? { |role| role.role.in?(%w[admin collaborator moderator]) }
      end

      def volunteer_shift
        @volunteer_shift ||= context.fetch(:volunteer_shift, nil)
      end

      def profile_user
        @profile_user ||= context.fetch(:profile_user, nil)
      end

      def component_settings
        @component_settings ||= component&.settings || component&.current_settings
      end
    end
  end
end
```

## Admin Interface Implementation

### Admin Controller with Filtering

```ruby
module Decidim
  module VolunteerScheduler
    module Admin
      class VolunteerShiftsController < Admin::ApplicationController
        include Decidim::Admin::Filterable

        helper_method :volunteer_shifts, :volunteer_shift

        def index
          enforce_permission_to :read, :volunteer_shift
          @volunteer_shifts = filtered_collection
        end

        def show
          enforce_permission_to :read, :volunteer_shift, volunteer_shift: volunteer_shift
        end

        def new
          enforce_permission_to :create, :volunteer_shift
          @form = form(VolunteerShiftForm).instance
        end

        def create
          enforce_permission_to :create, :volunteer_shift
          @form = form(VolunteerShiftForm).from_params(params)

          CreateVolunteerShift.call(@form, current_user) do
            on(:ok) do |volunteer_shift|
              flash[:notice] = I18n.t("volunteer_shifts.create.success", scope: "decidim.volunteer_scheduler.admin")
              redirect_to volunteer_shifts_path
            end

            on(:invalid) do
              flash.now[:alert] = I18n.t("volunteer_shifts.create.error", scope: "decidim.volunteer_scheduler.admin")
              render :new
            end
          end
        end

        def edit
          enforce_permission_to :update, :volunteer_shift, volunteer_shift: volunteer_shift
          @form = form(VolunteerShiftForm).from_model(volunteer_shift)
        end

        def update
          enforce_permission_to :update, :volunteer_shift, volunteer_shift: volunteer_shift
          @form = form(VolunteerShiftForm).from_params(params)

          UpdateVolunteerShift.call(@form, volunteer_shift) do
            on(:ok) do
              flash[:notice] = I18n.t("volunteer_shifts.update.success", scope: "decidim.volunteer_scheduler.admin")
              redirect_to volunteer_shifts_path
            end

            on(:invalid) do
              flash.now[:alert] = I18n.t("volunteer_shifts.update.error", scope: "decidim.volunteer_scheduler.admin")
              render :edit
            end
          end
        end

        def publish
          enforce_permission_to :publish, :volunteer_shift, volunteer_shift: volunteer_shift
          
          PublishVolunteerShift.call(volunteer_shift, current_user) do
            on(:ok) do
              flash[:notice] = I18n.t("volunteer_shifts.publish.success", scope: "decidim.volunteer_scheduler.admin")
            end
            
            redirect_back(fallback_location: volunteer_shifts_path)
          end
        end

        private

        def filtered_collection
          @filtered_collection ||= begin
            shifts = volunteer_shifts.includes(:category, :author)
            shifts = shifts.where(published_at: nil) if params[:filter] == "unpublished"
            shifts = shifts.published if params[:filter] == "published"
            shifts = shifts.where("start_time > ?", Time.current) if params[:filter] == "upcoming"
            shifts = shifts.where("start_time < ?", Time.current) if params[:filter] == "past"
            shifts
          end
        end

        def volunteer_shift
          @volunteer_shift ||= volunteer_shifts.find(params[:id])
        end

        def volunteer_shifts
          @volunteer_shifts ||= VolunteerShift.where(component: current_component)
        end
      end
    end
  end
end
```

## Background Job Implementation

### Reminder and Cleanup Jobs

```ruby
module Decidim
  module VolunteerScheduler
    class ShiftReminderJob < ApplicationJob
      queue_as :default

      def perform(volunteer_assignment_id)
        assignment = VolunteerAssignment.find(volunteer_assignment_id)
        return unless assignment.enrolled? || assignment.confirmed?

        VolunteerSchedulerMailer.shift_reminder(assignment).deliver_now
      end
    end

    class ShiftCleanupJob < ApplicationJob
      queue_as :low

      def perform
        # Remove assignments for past shifts that were never confirmed
        expired_assignments = VolunteerAssignment
          .joins(:volunteer_shift)
          .where("volunteer_shifts.end_time < ?", 1.week.ago)
          .where(status: :enrolled)

        expired_assignments.destroy_all

        # Mark completed shifts
        completed_shifts = VolunteerShift
          .where("end_time < ?", Time.current)
          .where.not(id: VolunteerAssignment.where(status: :completed).select(:decidim_volunteer_scheduler_shift_id))

        completed_shifts.each do |shift|
          CompleteVolunteerShiftJob.perform_later(shift.id)
        end
      end
    end

    class CompleteVolunteerShiftJob < ApplicationJob
      queue_as :default

      def perform(shift_id)
        shift = VolunteerShift.find(shift_id)
        return unless shift.end_time < Time.current

        shift.volunteer_assignments.where(status: [:enrolled, :confirmed]).each do |assignment|
          assignment.update!(
            status: :completed,
            checked_out_at: shift.end_time,
            xp_earned: shift.total_xp_points
          )

          # Process XP and referral rewards
          referral_service = ReferralProcessingService.new(assignment.user)
          referral_service.process_shift_completion(shift.total_xp_points)

          # Send completion notification
          Decidim::EventsManager.publish(
            event: "decidim.events.volunteer_scheduler.shift_completed",
            event_class: ShiftCompletedEvent,
            resource: shift,
            affected_users: [assignment.user]
          )
        end
      end
    end
  end
end
```

### Scheduled Job Configuration

```ruby
# config/schedule.rb (using whenever gem)
every 1.hour do
  runner "Decidim::VolunteerScheduler::ShiftReminderJob.perform_later"
end

every 1.day, at: '2:00 am' do
  runner "Decidim::VolunteerScheduler::ShiftCleanupJob.perform_later"
end

every 1.week, at: '3:00 am' do
  runner "Decidim::VolunteerScheduler::GenerateVolunteerReportsJob.perform_later"
end
```

## Event and Notification System

### Event Classes

```ruby
module Decidim
  module VolunteerScheduler
    class VolunteerShiftCreatedEvent < Decidim::Events::SimpleEvent
      include Decidim::Events::EmailEvent
      include Decidim::Events::NotificationEvent

      def email_subject
        I18n.t("email_subject", scope: i18n_scope, resource_title: resource_title)
      end

      def email_intro
        I18n.t("email_intro", scope: i18n_scope, resource_title: resource_title, author_name: author_name)
      end

      def notification_title
        I18n.t("notification_title", scope: i18n_scope, resource_title: resource_title)
      end

      def resource_text
        translated_attribute(resource.description)
      end

      private

      def i18n_scope
        "decidim.events.volunteer_scheduler.volunteer_shift_created"
      end

      def author_name
        resource.author.name
      end
    end

    class VolunteerSignedUpEvent < Decidim::Events::SimpleEvent
      include Decidim::Events::EmailEvent
      include Decidim::Events::NotificationEvent

      def email_subject
        I18n.t("email_subject", scope: i18n_scope, 
               resource_title: resource_title, participant_name: participant.name)
      end

      def email_intro
        I18n.t("email_intro", scope: i18n_scope, 
               participant_name: participant.name, resource_title: resource_title)
      end

      def notification_title
        I18n.t("notification_title", scope: i18n_scope, 
               participant_name: participant.name, resource_title: resource_title)
      end

      private

      def i18n_scope
        "decidim.events.volunteer_scheduler.volunteer_signed_up"
      end

      def participant
        @participant ||= Decidim::User.find(extra[:participant_id])
      end
    end
  end
end
```

## Testing Strategy and Patterns

### Model Testing with Factories

```ruby
# spec/factories/volunteer_shifts.rb
FactoryBot.define do
  factory :volunteer_shift, class: "Decidim::VolunteerScheduler::VolunteerShift" do
    title { generate_localized_title }
    description { Decidim::Faker::Localized.wrapped("<p>", "</p>") { generate(:body) } }
    start_time { 1.week.from_now }
    end_time { 1.week.from_now + 3.hours }
    max_volunteers { 5 }
    xp_points_per_hour { 10 }
    component { create(:volunteer_scheduler_component) }
    author { create(:user, :confirmed, organization: component.organization) }

    trait :published do
      published_at { Time.current }
    end

    trait :unpublished do
      published_at { nil }
    end

    trait :past do
      start_time { 1.week.ago }
      end_time { 1.week.ago + 3.hours }
    end

    trait :full do
      after(:create) do |shift, evaluator|
        create_list(:volunteer_assignment, shift.max_volunteers, volunteer_shift: shift)
      end
    end
  end

  factory :volunteer_scheduler_component, parent: :component do
    name { Decidim::Components::Namer.new(participatory_space.organization.available_locales, :volunteer_scheduler).i18n_name }
    manifest_name { :volunteer_scheduler }
    participatory_space { create(:participatory_process, :with_steps) }
  end

  factory :volunteer_assignment, class: "Decidim::VolunteerScheduler::VolunteerAssignment" do
    volunteer_shift { create(:volunteer_shift, :published) }
    user { create(:user, :confirmed, organization: volunteer_shift.organization) }
    signed_up_at { Time.current }
    status { :enrolled }
  end
end
```

### Comprehensive Model Testing

```ruby
# spec/models/decidim/volunteer_scheduler/volunteer_shift_spec.rb
require "spec_helper"

describe Decidim::VolunteerScheduler::VolunteerShift do
  subject { volunteer_shift }

  let(:volunteer_shift) { create(:volunteer_shift, :published) }

  it { is_expected.to be_valid }
  it { is_expected.to be_a(Decidim::Traceable) }
  it { is_expected.to be_a(Decidim::Loggable) }
  it { is_expected.to be_a(Decidim::Resourceable) }
  it { is_expected.to be_a(Decidim::Followable) }

  describe "validations" do
    it { is_expected.to validate_presence_of(:title) }
    it { is_expected.to validate_presence_of(:description) }
    it { is_expected.to validate_presence_of(:start_time) }
    it { is_expected.to validate_presence_of(:end_time) }
    it { is_expected.to validate_numericality_of(:max_volunteers).is_greater_than(0) }

    context "when end_time is before start_time" do
      let(:volunteer_shift) { build(:volunteer_shift, start_time: Time.current, end_time: 1.hour.ago) }

      it { is_expected.not_to be_valid }
      it "adds error to end_time" do
        volunteer_shift.valid?
        expect(volunteer_shift.errors[:end_time]).to include("is invalid")
      end
    end

    context "when start_time is in the past" do
      let(:volunteer_shift) { build(:volunteer_shift, start_time: 1.hour.ago) }

      it { is_expected.not_to be_valid }
    end
  end

  describe "#can_be_volunteered_by?" do
    let(:user) { create(:user, :confirmed, organization: volunteer_shift.organization) }

    context "when shift is published and has available spots" do
      it { expect(volunteer_shift.can_be_volunteered_by?(user)).to be true }
    end

    context "when user is not confirmed" do
      let(:user) { create(:user, organization: volunteer_shift.organization) }

      it { expect(volunteer_shift.can_be_volunteered_by?(user)).to be false }
    end

    context "when shift is full" do
      let(:volunteer_shift) { create(:volunteer_shift, :published, :full) }

      it { expect(volunteer_shift.can_be_volunteered_by?(user)).to be false }
    end

    context "when user already volunteered" do
      before { create(:volunteer_assignment, volunteer_shift: volunteer_shift, user: user) }

      it { expect(volunteer_shift.can_be_volunteered_by?(user)).to be false }
    end
  end

  describe "#duration_hours" do
    let(:volunteer_shift) { create(:volunteer_shift, start_time: Time.current, end_time: 3.hours.from_now) }

    it { expect(volunteer_shift.duration_hours).to eq(3.0) }
  end

  describe "#total_xp_points" do
    let(:volunteer_shift) { create(:volunteer_shift, start_time: Time.current, end_time: 2.hours.from_now, xp_points_per_hour: 15) }

    it { expect(volunteer_shift.total_xp_points).to eq(30) }
  end
end
```

### Command Testing

```ruby
# spec/commands/decidim/volunteer_scheduler/volunteer_for_shift_spec.rb
require "spec_helper"

describe Decidim::VolunteerScheduler::VolunteerForShift do
  let(:volunteer_shift) { create(:volunteer_shift, :published) }
  let(:user) { create(:user, :confirmed, organization: volunteer_shift.organization) }
  let(:command) { described_class.new(volunteer_shift, user) }

  describe "call" do
    context "when everything is ok" do
      it "broadcasts ok" do
        expect { command.call }.to broadcast(:ok)
      end

      it "creates a volunteer assignment" do
        expect { command.call }.to change(Decidim::VolunteerScheduler::VolunteerAssignment, :count).by(1)
      end

      it "creates assignment with correct attributes" do
        command.call
        assignment = Decidim::VolunteerScheduler::VolunteerAssignment.last

        expect(assignment.volunteer_shift).to eq(volunteer_shift)
        expect(assignment.user).to eq(user)
        expect(assignment.status).to eq("enrolled")
        expect(assignment.signed_up_at).to be_present
      end

      it "sends notification" do
        expect(Decidim::EventsManager).to receive(:publish).with(
          event: "decidim.events.volunteer_scheduler.volunteer_signed_up",
          event_class: Decidim::VolunteerScheduler::VolunteerSignedUpEvent,
          resource: volunteer_shift,
          affected_users: [user, volunteer_shift.author]
        )

        command.call
      end

      it "logs the action" do
        expect(Decidim.loggability).to receive(:log_action).with(
          "volunteer_signup",
          volunteer_shift,
          user,
          "User signed up for volunteer shift"
        )

        command.call
      end
    end

    context "when shift is full" do
      before { create_list(:volunteer_assignment, volunteer_shift.max_volunteers, volunteer_shift: volunteer_shift) }

      it "broadcasts invalid" do
        expect { command.call }.to broadcast(:invalid)
      end

      it "does not create assignment" do
        expect { command.call }.not_to change(Decidim::VolunteerScheduler::VolunteerAssignment, :count)
      end
    end

    context "when user already volunteered" do
      before { create(:volunteer_assignment, volunteer_shift: volunteer_shift, user: user) }

      it "broadcasts invalid" do
        expect { command.call }.to broadcast(:invalid)
      end
    end
  end
end
```

## Production Deployment and Security

### Database Migration Safety

```ruby
# Use strong_migrations gem
# Gemfile
gem "strong_migrations"

# config/initializers/strong_migrations.rb
StrongMigrations.configure do |config|
  config.auto_analyze = true
  config.statement_timeout = 1.hour
  config.lock_timeout = 10.seconds
  config.check_down = true
end
```

### Security Configuration

```ruby
# config/initializers/volunteer_scheduler.rb
Decidim::VolunteerScheduler.configure do |config|
  config.max_days_advance = 90
  config.default_reminder_time = 24.hours
  config.enable_shift_cleanup = true
  config.send_volunteer_notifications = true
  config.referral_code_entropy = 8 # characters
  config.max_referral_levels = 5
  config.enable_gdpr_compliance = true
end

# Security headers in application controller
class ApplicationController < ActionController::Base
  protect_from_forgery with: :exception
  
  before_action :configure_permitted_parameters, if: :devise_controller?
  before_action :set_referrer_from_params
  
  private
  
  def set_referrer_from_params
    return unless params[:ref].present?
    return if user_signed_in?
    
    session[:referrer_code] = params[:ref] if valid_referral_code?(params[:ref])
  end
  
  def valid_referral_code?(code)
    code.match?(/\A[A-Z0-9]{8}\z/) && 
    Decidim::VolunteerScheduler::VolunteerProfile.exists?(referral_code: code)
  end
end
```

### GDPR Compliance Implementation

```ruby
module Decidim
  module VolunteerScheduler
    class GdprComplianceService
      def initialize(user)
        @user = user
      end

      def export_user_data
        {
          profile: export_profile_data,
          shifts: export_shifts_data,
          referrals: export_referral_data,
          assignments: export_assignment_data
        }
      end

      def anonymize_user_data
        profile = VolunteerProfile.find_by(user: user)
        return unless profile

        # Anonymize but keep aggregated data for referral chain integrity
        profile.update!(
          referral_code: "DELETED_#{SecureRandom.hex(4)}",
          skills: [],
          availability_preferences: {}
        )

        # Remove personal notes from assignments
        VolunteerAssignment.where(user: user).update_all(notes: nil)
      end

      private

      attr_reader :user

      def export_profile_data
        profile = VolunteerProfile.find_by(user: user)
        return {} unless profile

        profile.attributes.except('id', 'created_at', 'updated_at')
      end

      def export_shifts_data
        VolunteerShift
          .joins(:volunteer_assignments)
          .where(volunteer_assignments: { user: user })
          .map { |shift| shift.attributes.slice('title', 'description', 'start_time', 'end_time') }
      end

      def export_referral_data
        {
          referrals_made: VolunteerProfile.where(referred_by: user).count,
          total_referral_earnings: ReferralEarning.where(referrer: user).sum(:xp_earned)
        }
      end

      def export_assignment_data
        VolunteerAssignment
          .where(user: user)
          .map { |assignment| assignment.attributes.except('id', 'decidim_user_id') }
      end
    end
  end
end
```

This comprehensive implementation guide provides production-ready patterns for all aspects of the decidim-volunteer_scheduler module, following established Decidim conventions and best practices from successful production modules. The patterns include proper database design, security measures, testing strategies, and deployment considerations necessary for Phase 1 production quality.