# Decidim Volunteer Scheduler

A comprehensive volunteer management module for Decidim organizations implementing gamified task assignments, referral systems, and XP-based progression.

## Features

### 🎮 Gamification System
- **XP-based progression** with 3 levels and capability unlocks
- **Level 1**: Basic tasks (0-99 XP)
- **Level 2**: Intermediate tasks + team creation (100-499 XP)
- **Level 3**: Advanced tasks + leadership (500+ XP)
- **Activity multiplier system** with rolling 30-day windows

### 🔗 Referral System
- **5-level referral chain** with automatic commission distribution
- Commission rates: L1: 10%, L2: 8%, L3: 6%, L4: 4%, L5: 2%
- Referral code generation and tracking
- Network size tracking and multiplier calculations

### 📋 Task Management
- Organization-level and component-specific task templates
- Task categories: outreach, technical, administrative, content creation, training, mentoring
- Flexible frequency options: one-time, daily, weekly, monthly
- Task submission and review workflow with admin approval

### 💰 Token Rewards
- Scicent token integration
- Automatic commission distribution
- Transaction tracking and audit trail
- Budget allocation with competitive bonuses

### 📊 Analytics & Reporting
- Real-time volunteer dashboard
- Leaderboard with daily/weekly/monthly views
- Comprehensive metrics and statistics
- Data export capabilities

## Installation

Add this line to your application's Gemfile:

```ruby
gem "decidim-volunteer_scheduler", github: "scicent/decidim-volunteer_scheduler"
```

And then execute:
```bash
bundle install
bundle exec rails decidim:volunteer_scheduler:install:migrations
bundle exec rails db:migrate
```

**That's it!** The module automatically registers itself with Decidim - no manual route configuration needed.

## Configuration

### Component Settings

Configure through the Decidim admin panel:

- **XP per task**: Base XP reward for task completion (default: 20)
- **Max daily tasks**: Maximum tasks a volunteer can accept per day (default: 5)
- **Referral commission rates**: Commission percentages for each level
- **Level thresholds**: XP requirements for level progression
- **Task deadline days**: Default deadline for task completion (default: 7)

### Environment Variables

```bash
# Optional: External token API integration
SCICENT_API_KEY=your_api_key
SCICENT_WEBHOOK_SECRET=your_webhook_secret

# Optional: Performance tuning
VOLUNTEER_SCHEDULER_MAX_ASSIGNMENTS=10
ACTIVITY_MULTIPLIER_MAX=3.0
```

## Usage

VolunteerScheduler is available as a Component for Decidim Participatory Spaces (Processes, Assemblies, etc.).

### Admin Interface

Access the volunteer scheduler admin interface at `/admin/volunteer_scheduler` to:
- Create and manage task templates
- Review task assignments
- Monitor volunteer profiles and statistics

## Testing

### Test Users

The seed data creates these test users for immediate testing:

- `volunteer1@gmail.com` - Alice Volunteer (password: `decidim_alice_password123!`)
- `volunteer2@gmail.com` - Bob Volunteer (password: `decidim_bob_password456!`) 
- `volunteer3@gmail.com` - Carol Volunteer (password: `decidim_carol_password789!`)

### Manual Testing

1. **Login as Admin**: Navigate to `/admin` 
2. **Access Volunteer Scheduler**: Find "Volunteer Scheduler" in admin sidebar
3. **Create Task Templates**: Add organization-wide task templates
4. **Login as Volunteer**: Use any of the test accounts above
5. **Accept Tasks**: Test task assignment and completion workflow

### Task Templates

Task templates are organization-level resources that define:
- Title and description
- XP reward and level requirement
- Category and frequency
- Publication status

## Contributing

Contributions are welcome! Please follow [Decidim's contribution guide](https://github.com/decidim/decidim/blob/develop/CONTRIBUTING.adoc).

## Security

Security is very important to us. If you have any security issues, please disclose responsibly by sending an email to security@example.com rather than creating a GitHub issue.

## License

This engine is distributed under the GNU AFFERO GENERAL PUBLIC LICENSE.