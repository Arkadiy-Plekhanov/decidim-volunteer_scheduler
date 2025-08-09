# frozen_string_literal: true

class CreateDecidimVolunteerSchedulerReferrals < ActiveRecord::Migration[6.1]
  def change
    create_table :decidim_volunteer_scheduler_referrals do |t|
      t.references :referrer, null: false, foreign_key: { to_table: :decidim_volunteer_scheduler_volunteer_profiles }, index: { name: 'idx_referrals_referrer' }
      t.references :referred, null: false, foreign_key: { to_table: :decidim_volunteer_scheduler_volunteer_profiles }, index: { name: 'idx_referrals_referred' }
      
      t.integer :level, null: false
      t.decimal :commission_rate, null: false, precision: 5, scale: 4
      t.decimal :total_commission, null: false, default: 0.0, precision: 10, scale: 2
      t.boolean :active, null: false, default: true
      
      t.timestamps null: false
      
      t.index [:referrer_id, :level], name: 'idx_referrals_referrer_level'
      t.index [:referred_id, :level], name: 'idx_referrals_referred_level', unique: true
      t.index [:level, :active], name: 'idx_referrals_level_active'
      t.index [:referrer_id, :referred_id], name: 'idx_referrals_referrer_referred', unique: true
      
      t.check_constraint "level >= 1 AND level <= 5", name: "chk_referrals_level_range"
      t.check_constraint "commission_rate >= 0 AND commission_rate <= 1", name: "chk_referrals_commission_rate"
    end
  end
end
