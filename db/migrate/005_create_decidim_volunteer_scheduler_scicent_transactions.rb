# frozen_string_literal: true

class CreateDecidimVolunteerSchedulerScicentTransactions < ActiveRecord::Migration[6.1]
  def change
    create_table :decidim_volunteer_scheduler_scicent_transactions do |t|
      t.references :volunteer_profile, null: false, foreign_key: { to_table: :decidim_volunteer_scheduler_volunteer_profiles }, index: { name: 'idx_scicent_trans_profile' }
      
      t.integer :transaction_type, null: false
      t.decimal :amount, null: false, precision: 10, scale: 2
      t.integer :xp_amount, null: true
      t.decimal :commission_amount, null: true, precision: 10, scale: 2
      t.decimal :sale_amount, null: true, precision: 10, scale: 2
      t.text :description, null: false
      
      t.timestamps null: false
      
      t.index [:volunteer_profile_id, :transaction_type], name: 'idx_scicent_transactions_profile_type'
      t.index [:transaction_type, :created_at], name: 'idx_scicent_transactions_type_date'
      t.index [:created_at], name: 'idx_scicent_transactions_date'
    end
  end
end
