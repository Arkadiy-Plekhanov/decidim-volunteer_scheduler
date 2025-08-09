# Overview

Decidim Volunteer Scheduler is a comprehensive gamified volunteer management component built as a native Decidim module. The system enables organizations to manage volunteers through task assignment, XP/leveling systems, and a sophisticated 5-level referral program with token-based rewards. It integrates deeply with Decidim's core features including user management, notifications, follow-ups, and admin interfaces while maintaining full compatibility with Decidim's architectural patterns and conventions.

# User Preferences

Preferred communication style: Simple, everyday language.

# System Architecture

## Component Structure
The module follows Decidim's standard component architecture pattern, generated using `rails generate decidim:component volunteer_scheduler`. It's structured as a self-contained engine with separate user and admin interfaces, leveraging Decidim's component manifest system for configuration and settings management.

## Database Architecture
The system uses five core models with careful attention to Decidim conventions:
- **VolunteerProfile**: Extends Decidim users with volunteer-specific data (XP, level, referral codes)
- **TaskTemplate**: Admin-created task definitions with level requirements and XP rewards
- **TaskAssignment**: Links volunteers to specific tasks with completion tracking
- **Referral**: Implements 5-level deep referral chains with commission tracking
- **ScicentTransaction**: Ledger system for token distribution and commission payments

All models follow Decidim naming conventions with `decidim_volunteer_scheduler_` table prefixes and proper foreign key relationships to `decidim_users` and `decidim_components`.

## Business Logic Services
Core business operations are encapsulated in service classes following SOLID principles:
- **XP and leveling calculations** with configurable thresholds
- **Referral chain processing** with multi-level commission distribution
- **Activity multiplier calculations** based on referral performance
- **Token distribution algorithms** combining base activity with referral bonuses

## Frontend Architecture
Uses Decidim's standard view patterns with:
- **Cell-based components** for reusable UI elements (progress bars, dashboards, task lists)
- **JavaScript enhancement** via Webpacker entry points for interactive features
- **Responsive design** following Decidim's Bootstrap-based styling conventions
- **Real-time updates** through Decidim's notification system integration

## Admin Interface
Comprehensive admin functionality built on Decidim's admin engine patterns:
- **Task template management** with bulk operations
- **Assignment review workflows** for approving volunteer submissions
- **Volunteer monitoring** with level and activity tracking
- **System configuration** through component settings

## Integration Points
Deep integration with Decidim core features:
- **User system extension** without modifying core User model
- **Follow-up component integration** for task submission workflows
- **Notification system** for volunteer communications
- **Permission system** for role-based access control
- **Export capabilities** for volunteer data management

# External Dependencies

## Core Decidim Dependencies
- **Decidim Core Engine**: Base platform functionality and user management
- **Decidim Admin Engine**: Administrative interface patterns and components
- **Decidim Follow-ups**: Task submission and reporting workflows
- **Decidim Notifications**: In-app notification system for volunteer communications

## Database Requirements
- **PostgreSQL**: Primary database with JSONB support for flexible volunteer data storage
- **Redis**: Required for ActionCable real-time features and caching (production environments)

## Asset Management
- **Webpacker**: JavaScript bundling and asset compilation
- **Bootstrap**: UI framework (inherited from Decidim core)
- **Custom JavaScript modules**: Interactive features like clipboard operations, progress animations, and bulk actions

## Background Processing
- **ActiveJob**: Asynchronous processing for XP calculations, commission distributions, and token allocations
- **Sidekiq/DelayedJob**: Job queue processing (environment dependent)

## Development Tools
- **RSpec**: Comprehensive test suite for models, services, and controllers
- **FactoryBot**: Test data generation
- **Faker**: Realistic test data creation
- **DatabaseCleaner**: Test database management

## Optional Integrations
- **External Token APIs**: Webhook endpoints for Scicent token sales integration
- **Email Services**: Enhanced notification delivery (leverages Decidim's existing email configuration)
- **Analytics Platforms**: Volunteer engagement tracking and reporting