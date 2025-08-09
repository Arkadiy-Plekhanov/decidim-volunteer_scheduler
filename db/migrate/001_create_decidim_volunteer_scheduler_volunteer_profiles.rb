# frozen_string_literal: true

class CreateDecidimVolunteerSchedulerVolunteerProfiles < ActiveRecord::Migration[6.1]
  def change
    create_table :decidim_volunteer_scheduler_volunteer_profiles do |t|
      t.references :user, null: false, foreign_key: { to_table: :decidim_users }, index: { name: 'idx_vol_profiles_user' }
      t.references :component, null: false, foreign_key: { to_table: :decidim_components }, index: { name: 'idx_vol_profiles_component' }
      t.references :referrer, null: true, foreign_key: { to_table: :decidim_volunteer_scheduler_volunteer_profiles }, index: { name: 'idx_vol_profiles_referrer' }
      
      t.string :referral_code, null: false, index: { unique: true, name: 'idx_vol_profiles_referral_code' }
      t.integer :level, null: false, default: 1
      t.integer :total_xp, null: false, default: 0
      t.decimal :activity_multiplier, null: false, default: 1.0, precision: 5, scale: 2
      t.datetime :last_activity_at, null: false, default: -> { 'CURRENT_TIMESTAMP' }
      
      t.timestamps null: false
      
      t.index [:user_id, :component_id], unique: true, name: 'idx_volunteer_profiles_user_component'
      t.index [:level, :total_xp], name: 'idx_volunteer_profiles_level_xp'
      t.index :last_activity_at, name: 'idx_volunteer_profiles_activity'
    end
  end
end
