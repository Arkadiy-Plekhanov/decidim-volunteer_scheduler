# Decidim 0.30+ Volunteer Scheduler Development Guide

Based on comprehensive research of official documentation, community modules, and established patterns from the decidim/decidim repository, this guide provides practical implementation strategies for creating a robust volunteer scheduler module in Decidim 0.30+.

## Component architecture and generation patterns

**Decidim provides built-in scaffolding tools** for component development through its generator system. Use `decidim --component volunteer_scheduler` to create the initial structure, which automatically generates the proper directory layout with controllers, models, views, and engine configuration following established conventions.

The generated structure places all models within the `Decidim::VolunteerScheduler` namespace, ensuring proper isolation while maintaining integration with core platform features. **Database tables must follow the `decidim_volunteer_scheduler_` prefix pattern** with appropriate foreign keys to `decidim_component_id` and `decidim_users` for proper scoping and user associations.

**Component registration requires defining both global and step-specific settings** through the manifest system. Global settings might include maximum volunteer slots, notification preferences, and attachment configurations, while step settings control feature availability during different participation phases like registration periods, active volunteering, and completion phases.

The component manifest also defines export capabilities, permission classes, and lifecycle hooks. For a volunteer scheduler, this includes exporting volunteer data, implementing role-based permissions for coordinators versus volunteers, and handling component creation/destruction events properly.

## User profile extensions and volunteer management

**Extending Decidim::User follows specific association patterns** to maintain platform compatibility. Create a `VolunteerProfile` model with a `belongs_to :user` relationship, storing volunteer-specific attributes like skills, availability preferences, emergency contacts, and participation history.

```ruby
# Recommended association pattern
has_one :volunteer_profile, dependent: :destroy
accepts_nested_attributes_for :volunteer_profile
delegate :skills, :availability, :emergency_contact, to: :volunteer_profile, allow_nil: true
```

**Validation should be implemented through concern modules** rather than modifying the core User model directly. This approach maintains upgrade compatibility and allows for clean separation of volunteer-specific logic. The `decidim-module-extra_user_fields` community module demonstrates effective patterns for extending user functionality while preserving core platform integrity.

For complex volunteer data like availability schedules or skill matrices, **use JSONB fields with Decidim's translatable field helpers** to support multilingual deployments. Store structured data as serialized attributes while providing proper validation and query interfaces.

## Invitation systems and coordinator workflows

**Decidim's built-in invitation system uses Devise::Invitable** with custom extensions for organization-scoped invitations. The volunteer scheduler can leverage this foundation by implementing specialized invitation commands that create both user invitations and volunteer role assignments simultaneously.

Custom invitation flows should extend `Decidim::InviteUser` command patterns, adding volunteer-specific metadata like assigned shifts, coordinator relationships, or initial skill assessments. **The `decidim-meetings` module provides proven patterns** for context-specific invitations that can be adapted for volunteer recruitment workflows.

For referral systems enabling volunteers to invite others, implement a `UserReferral` model with proper validation to prevent self-referrals and ensure organization membership consistency. Include acceptance tracking and reward mechanisms for successful referrals to encourage community growth.

## Follow-up functionality and task management

**Decidim's follow-up system integrates through the platform's core following and notification architecture** rather than through specific controller concerns. Volunteers can follow shifts, events, or coordinator announcements, receiving automatic notifications for relevant updates.

Implement task submission workflows using **Decidim's event system with custom event classes** that trigger appropriate notifications to coordinators and fellow volunteers. Task completion, shift confirmations, and feedback submissions should all generate events that flow through the platform's notification pipeline.

The follow-up system supports both traditional email notifications and real-time updates when ActionCable is enabled, providing flexibility for different organizational communication preferences and technical capabilities.

## Real-time features with ActionCable

**ActionCable integration requires explicit configuration** as it's not enabled by default in Decidim applications. Set up Redis as the adapter for production environments, as PostgreSQL NOTIFY has message size limitations that affect real-time functionality.

Create component-specific channels for volunteer coordination features like shift updates, emergency communications, or live volunteer check-ins. **The `decidim-module-notify` by Platoniq provides the most comprehensive ActionCable implementation example** in the Decidim ecosystem, demonstrating proper channel organization and JavaScript client integration.

Channel subscription should be scoped by component and organization to prevent cross-contamination between different participatory spaces. Implement proper authentication in the connection class and authorization checks before allowing channel subscriptions to sensitive volunteer information.

Real-time features particularly benefit volunteer scheduling through instant shift updates, coordinator broadcasts, and emergency response coordination that requires immediate communication across the volunteer network.

## Background job implementation for scheduling

**Decidim uses ActiveJob with support for multiple queue backends**, with delayed_job recommended for simple setups and Sidekiq for high-performance scenarios. The volunteer scheduler will need several job types: shift reminder emails, availability matching, schedule conflict resolution, and periodic data cleanup.

Implement queue-specific processing with dedicated queues like `volunteer_reminders`, `schedule_processing`, and `data_exports` to prioritize time-sensitive volunteer communications over administrative tasks. **Jobs must be designed as idempotent operations** using resource IDs rather than object serialization to handle retry scenarios gracefully.

Community modules demonstrate effective patterns for complex background processing, particularly the metrics calculation jobs and machine translation services that can be adapted for volunteer matching algorithms and multilingual volunteer communications.

## Database design and migration strategies

**Database migrations follow strict naming conventions** with timestamps and descriptive action names ending in `.decidim.rb`. Tables require the component namespace prefix and proper indexing strategies for performance.

Core volunteer scheduler tables should include:
- `decidim_volunteer_scheduler_shifts` for time-based volunteer opportunities
- `decidim_volunteer_scheduler_assignments` for volunteer-shift relationships  
- `decidim_volunteer_scheduler_skills` for capability tracking
- `decidim_volunteer_scheduler_feedbacks` for post-activity evaluations

**Index strategy must consider common query patterns** like finding available shifts by date range, matching volunteers by skills, and filtering assignments by completion status. Use composite indexes for multi-column queries and JSONB gin indexes for structured volunteer metadata searches.

Foreign key relationships to `decidim_components` and `decidim_users` enable proper authorization and data scoping across the platform's participatory space architecture.

## Notification and event system integration

**Decidim's event system uses ActiveSupport::Notifications with custom event classes** that define both traditional email notifications and real-time ActionCable broadcasts. Volunteer-specific events might include shift assignments, cancellations, reminder notices, and completion confirmations.

Event classes inherit from `Decidim::Events::SimpleEvent` and define notification titles, resource URLs, and action buttons for various delivery contexts. **Events automatically integrate with the platform's email delivery system** while supporting ActionCable broadcasting for real-time updates.

The notification system supports user preference management, allowing volunteers to control which events generate emails versus in-app notifications. This granular control improves user experience while reducing notification fatigue in active volunteer communities.

## Testing strategies and quality assurance

**Comprehensive testing requires multiple approaches** covering unit tests for models and commands, controller tests for admin and public interfaces, and system tests for complete user workflows. The testing framework uses RSpec with FactoryBot for data generation.

Factory definitions should follow Decidim patterns with proper trait usage for different volunteer states, shift types, and assignment scenarios. **Shared examples from community modules provide proven patterns** for testing common functionality like admin interfaces, permission systems, and component settings.

Background job testing uses ActiveJob test helpers with the `:perform_enqueued` tag for integration tests that verify complete workflows including asynchronous processing. Mock external services like SMS notifications or calendar integrations to ensure test reliability while maintaining realistic scenarios.

System tests using Capybara verify complete user journeys from volunteer registration through task completion, ensuring the module integrates properly with Decidim's authentication, authorization, and notification systems.

## Component settings and administrative control

**Settings configuration supports both global and step-specific options** through the component manifest. Global settings might include volunteer capacity limits, required skill verification, and attachment policies for volunteer documentation.

Step settings provide phase-specific control over volunteer registration periods, assignment modifications, and feedback collection timing. **Administrative interfaces automatically generate from setting definitions** with proper internationalization support and help text for complex configuration options.

Advanced settings can include dynamic enums that populate from database content, readonly fields that prevent modification after certain conditions, and conditional settings that enable features based on other configuration values.

The settings system integrates with Decidim's permission framework, allowing fine-grained control over which administrative roles can modify different aspects of volunteer scheduling configuration.

## Community module examples and patterns

**Several community modules demonstrate effective development patterns** applicable to volunteer scheduling functionality. The `decidim-module-extra_user_fields` shows proper user extension techniques, while `decidim-module-plans` provides complex workflow management examples.

The `decidim-ice/decidim-module-decidim_awesome` demonstrates advanced testing configurations and performance considerations, offering guidance for modules that handle significant user interaction and data processing requirements.

These community examples emphasize following Decidim conventions while providing specialized functionality, maintaining upgrade compatibility through proper extension patterns rather than core platform modifications.

**Module development succeeds through consistent adherence to established patterns**, comprehensive testing coverage, and active engagement with the Decidim community for feedback and compatibility verification across different deployment scenarios.

The volunteer scheduler module should leverage these proven patterns while addressing the specific needs of volunteer coordination, creating a robust platform extension that enhances community participation capabilities within Decidim's participatory democracy framework.