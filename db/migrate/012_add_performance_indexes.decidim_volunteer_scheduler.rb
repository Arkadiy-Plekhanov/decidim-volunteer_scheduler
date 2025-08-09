# frozen_string_literal: true

# Migration to add performance indexes following PostgreSQL best practices
class AddPerformanceIndexes < ActiveRecord::Migration[6.1]
  disable_ddl_transaction!
  
  def up
    # Indexes for VolunteerProfile
    add_index :decidim_volunteer_scheduler_volunteer_profiles, 
              [:user_id, :organization_id], 
              algorithm: :concurrently,
              unique: true,
              name: "idx_volunteer_profiles_user_org_unique",
              if_not_exists: true
              
    add_index :decidim_volunteer_scheduler_volunteer_profiles,
              :referral_code,
              algorithm: :concurrently,
              unique: true,
              name: "idx_volunteer_profiles_referral_code",
              if_not_exists: true
              
    add_index :decidim_volunteer_scheduler_volunteer_profiles,
              [:level, :total_xp],
              algorithm: :concurrently,
              name: "idx_volunteer_profiles_level_xp",
              if_not_exists: true
              
    # Indexes for TaskTemplate
    add_index :decidim_volunteer_scheduler_task_templates,
              [:organization_id, :status],
              algorithm: :concurrently,
              name: "idx_task_templates_org_status",
              if_not_exists: true
              
    add_index :decidim_volunteer_scheduler_task_templates,
              [:level_required, :status],
              algorithm: :concurrently,
              name: "idx_task_templates_level_status",
              if_not_exists: true
              
    # Indexes for TaskAssignment
    add_index :decidim_volunteer_scheduler_task_assignments,
              [:assignee_id, :status],
              algorithm: :concurrently,
              name: "idx_task_assignments_assignee_status",
              if_not_exists: true
              
    add_index :decidim_volunteer_scheduler_task_assignments,
              [:status, :assigned_at],
              algorithm: :concurrently,
              name: "idx_task_assignments_status_date",
              if_not_exists: true
              
    add_index :decidim_volunteer_scheduler_task_assignments,
              :due_date,
              algorithm: :concurrently,
              where: "status IN ('pending', 'submitted')",
              name: "idx_task_assignments_due_date_active",
              if_not_exists: true
              
    # Indexes for Referral
    add_index :decidim_volunteer_scheduler_referrals,
              [:referrer_id, :level],
              algorithm: :concurrently,
              name: "idx_referrals_referrer_level",
              if_not_exists: true
              
    add_index :decidim_volunteer_scheduler_referrals,
              [:referred_id, :status],
              algorithm: :concurrently,
              name: "idx_referrals_referred_status",
              if_not_exists: true
              
    add_index :decidim_volunteer_scheduler_referrals,
              [:organization_id, :status, :created_at],
              algorithm: :concurrently,
              name: "idx_referrals_org_status_date",
              if_not_exists: true
              
    # Indexes for ScicentTransaction
    add_index :decidim_volunteer_scheduler_scicent_transactions,
              [:user_id, :transaction_type, :status],
              algorithm: :concurrently,
              name: "idx_scicent_trans_user_type_status",
              if_not_exists: true
              
    add_index :decidim_volunteer_scheduler_scicent_transactions,
              [:status, :created_at],
              algorithm: :concurrently,
              name: "idx_scicent_trans_status_date",
              if_not_exists: true
  end
  
  def down
    # Remove indexes in reverse order
    remove_index :decidim_volunteer_scheduler_scicent_transactions, 
                 name: "idx_scicent_trans_status_date",
                 algorithm: :concurrently,
                 if_exists: true
                 
    remove_index :decidim_volunteer_scheduler_scicent_transactions,
                 name: "idx_scicent_trans_user_type_status",
                 algorithm: :concurrently,
                 if_exists: true
                 
    remove_index :decidim_volunteer_scheduler_referrals,
                 name: "idx_referrals_org_status_date",
                 algorithm: :concurrently,
                 if_exists: true
                 
    remove_index :decidim_volunteer_scheduler_referrals,
                 name: "idx_referrals_referred_status",
                 algorithm: :concurrently,
                 if_exists: true
                 
    remove_index :decidim_volunteer_scheduler_referrals,
                 name: "idx_referrals_referrer_level",
                 algorithm: :concurrently,
                 if_exists: true
                 
    remove_index :decidim_volunteer_scheduler_task_assignments,
                 name: "idx_task_assignments_due_date_active",
                 algorithm: :concurrently,
                 if_exists: true
                 
    remove_index :decidim_volunteer_scheduler_task_assignments,
                 name: "idx_task_assignments_status_date",
                 algorithm: :concurrently,
                 if_exists: true
                 
    remove_index :decidim_volunteer_scheduler_task_assignments,
                 name: "idx_task_assignments_assignee_status",
                 algorithm: :concurrently,
                 if_exists: true
                 
    remove_index :decidim_volunteer_scheduler_task_templates,
                 name: "idx_task_templates_level_status",
                 algorithm: :concurrently,
                 if_exists: true
                 
    remove_index :decidim_volunteer_scheduler_task_templates,
                 name: "idx_task_templates_org_status",
                 algorithm: :concurrently,
                 if_exists: true
                 
    remove_index :decidim_volunteer_scheduler_volunteer_profiles,
                 name: "idx_volunteer_profiles_level_xp",
                 algorithm: :concurrently,
                 if_exists: true
                 
    remove_index :decidim_volunteer_scheduler_volunteer_profiles,
                 name: "idx_volunteer_profiles_referral_code",
                 algorithm: :concurrently,
                 if_exists: true
                 
    remove_index :decidim_volunteer_scheduler_volunteer_profiles,
                 name: "idx_volunteer_profiles_user_org_unique",
                 algorithm: :concurrently,
                 if_exists: true
  end
end