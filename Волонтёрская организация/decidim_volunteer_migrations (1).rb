# db/migrate/001_create_decidim_volunteer_scheduler_task_templates.rb
class CreateDecidimVolunteerSchedulerTaskTemplates < ActiveRecord::Migration[6.1]
  def change
    create_table :decidim_volunteer_scheduler_task_templates do |t|
      t.references :decidim_component, null: false, foreign_key: true
      t.jsonb :title, null: false
      t.jsonb :description
      t.integer :level, null: false, default: 1
      t.integer :frequency, null: false, default: 0
      t.integer :category, null: false, default: 0
      t.integer :xp_reward, null: false, default: 10
      t.decimal :scicent_reward, precision: 10, scale: 2, default: 0
      t.boolean :active, null: false, default: true
      t.datetime :available_from
      t.datetime :available_until
      t.integer :max_assignments
      t.text :requirements
      t.jsonb :instructions, default: {}
      t.jsonb :metadata, default: {}
      t.timestamps
    end

    add_index :decidim_volunteer_scheduler_task_templates, :level
    add_index :decidim_volunteer_scheduler_task_templates, :frequency
    add_index :decidim_volunteer_scheduler_task_templates, :category
    add_index :decidim_volunteer_scheduler_task_templates, :active
    add_index :decidim_volunteer_scheduler_task_templates, :decidim_component_id
  end
end

# db/migrate/002_create_decidim_volunteer_scheduler_task_assignments.rb
class CreateDecidimVolunteerSchedulerTaskAssignments < ActiveRecord::Migration[6.1]
  def change
    create_table :decidim_volunteer_scheduler_task_assignments do |t|
      t.references :task_template, null: false, 
                   foreign_key: { to_table: :decidim_volunteer_scheduler_task_templates }
      t.references :assignee, null: false, foreign_key: { to_table: :decidim_users }
      t.references :reviewer, null: true, foreign_key: { to_table: :decidim_users }
      t.integer :status, null: false, default: 0
      t.datetime :assigned_at, null: false
      t.datetime :due_date
      t.datetime :started_at
      t.datetime :submitted_at
      t.datetime :completed_at
      t.text :report
      t.text :admin_notes
      t.integer :xp_earned, default: 0
      t.decimal :scicent_earned, precision: 10, scale: 2, default: 0
      t.jsonb :submission_data, default: {}
      t.timestamps
    end

    add_index :decidim_volunteer_scheduler_task_assignments, :status
    add_index :decidim_volunteer_scheduler_task_assignments, :assignee_id
    add_index :decidim_volunteer_scheduler_task_assignments, :due_date
    add_index :decidim_volunteer_scheduler_task_assignments, [:assignee_id, :status]
    add_index :decidim_volunteer_scheduler_task_assignments, [:task_template_id, :status]
  end
end

# db/migrate/003_create_decidim_volunteer_scheduler_volunteer_profiles.rb
class CreateDecidimVolunteerSchedulerVolunteerProfiles < ActiveRecord::Migration[6.1]
  def change
    create_table :decidim_volunteer_scheduler_volunteer_profiles do |t|
      t.references :user, null: false, foreign_key: { to_table: :decidim_users }
      t.integer :level, null: false, default: 1
      t.integer :total_xp, null: false, default: 0
      t.decimal :total_scicent_earned, precision: 12, scale: 2, default: 0
      t.decimal :referral_scicent_earned, precision: 12, scale: 2, default: 0
      t.integer :tasks_completed, null: false, default: 0
      t.decimal :activity_multiplier, precision: 3, scale: 2, default: 1.0
      t.string :referral_code, null: false
      t.references :referrer, null: true, foreign_key: { to_table: :decidim_users }
      t.jsonb :capabilities, default: {}
      t.jsonb :achievements, default: []
      t.datetime :last_activity_at
      t.timestamps
    end

    add_index :decidim_volunteer_scheduler_volunteer_profiles, :user_id, unique: true
    add_index :decidim_volunteer_scheduler_volunteer_profiles, :level
    add_index :decidim_volunteer_scheduler_volunteer_profiles, :referral_code, unique: true
    add_index :decidim_volunteer_scheduler_volunteer_profiles, :referrer_id
    add_index :decidim_volunteer_scheduler_volunteer_profiles, [:level, :total_xp]
  end
end

# db/migrate/004_create_decidim_volunteer_scheduler_referrals.rb
class CreateDecidimVolunteerSchedulerReferrals < ActiveRecord::Migration[6.1]
  def change
    create_table :decidim_volunteer_scheduler_referrals do |t|
      t.references :referrer, null: false, foreign_key: { to_table: :decidim_users }
      t.references :referred, null: false, foreign_key: { to_table: :decidim_users }
      t.integer :level, null: false, default: 1
      t.decimal :commission_rate, precision: 5, scale: 4, null: false
      t.decimal :total_commission, precision: 12, scale: 2, default: 0
      t.boolean :active, null: false, default: true
      t.datetime :activation_date
      t.timestamps
    end

    add_index :decidim_volunteer_scheduler_referrals, [:referrer_id, :referred_id], 
              unique: true, name: 'idx_referrals_referrer_referred'
    add_index :decidim_volunteer_scheduler_referrals, :level
    add_index :decidim_volunteer_scheduler_referrals, :referred_id
    add_index :decidim_volunteer_scheduler_referrals, [:referrer_id, :active]
  end
end

# db/migrate/005_create_decidim_volunteer_scheduler_scicent_transactions.rb
class CreateDecidimVolunteerSchedulerScicentTransactions < ActiveRecord::Migration[6.1]
  def change
    create_table :decidim_volunteer_scheduler_scicent_transactions do |t|
      t.references :user, null: false, foreign_key: { to_table: :decidim_users }
      t.references :source, null: false, polymorphic: true
      t.integer :transaction_type, null: false
      t.decimal :amount, precision: 12, scale: 2, null: false
      t.integer :status, null: false, default: 0
      t.text :description
      t.jsonb :metadata, default: {}
      t.datetime :processed_at
      t.timestamps
    end

    add_index :decidim_volunteer_scheduler_scicent_transactions, :user_id
    add_index :decidim_volunteer_scheduler_scicent_transactions, :transaction_type
    add_index :decidim_volunteer_scheduler_scicent_transactions, :status
    add_index :decidim_volunteer_scheduler_scicent_transactions, [:user_id, :transaction_type]
    add_index :decidim_volunteer_scheduler_scicent_transactions, [:source_type, :source_id]
  end
end

# db/migrate/006_create_decidim_volunteer_scheduler_teams.rb
class CreateDecidimVolunteerSchedulerTeams < ActiveRecord::Migration[6.1]
  def change
    create_table :decidim_volunteer_scheduler_teams do |t|
      t.references :decidim_component, null: false, foreign_key: true
      t.references :leader, null: false, foreign_key: { to_table: :decidim_users }
      t.jsonb :name, null: false
      t.jsonb :description
      t.integer :max_members, default: 10
      t.boolean :public_join, default: false
      t.jsonb :requirements, default: {}
      t.integer :status, null: false, default: 0
      t.timestamps
    end

    add_index :decidim_volunteer_scheduler_teams, :leader_id
    add_index :decidim_volunteer_scheduler_teams, :decidim_component_id
    add_index :decidim_volunteer_scheduler_teams, :status
  end
end

# db/migrate/007_create_decidim_volunteer_scheduler_team_memberships.rb
class CreateDecidimVolunteerSchedulerTeamMemberships < ActiveRecord::Migration[6.1]
  def change
    create_table :decidim_volunteer_scheduler_team_memberships do |t|
      t.references :team, null: false, 
                   foreign_key: { to_table: :decidim_volunteer_scheduler_teams }
      t.references :user, null: false, foreign_key: { to_table: :decidim_users }
      t.integer :role, null: false, default: 0
      t.datetime :joined_at, null: false
      t.boolean :active, null: false, default: true
      t.timestamps
    end

    add_index :decidim_volunteer_scheduler_team_memberships, [:team_id, :user_id], 
              unique: true, name: 'idx_team_memberships_team_user'
    add_index :decidim_volunteer_scheduler_team_memberships, :user_id
    add_index :decidim_volunteer_scheduler_team_memberships, :role
  end
end