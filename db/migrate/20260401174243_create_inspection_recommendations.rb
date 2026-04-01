# db/migrate/20260401000000_create_inspection_recommendations.rb
class CreateInspectionRecommendations < ActiveRecord::Migration[8.1]
  def change
    create_table :inspection_recommendations do |t|
      t.references :inspection, null: false, foreign_key: true
      t.references :suggested_by, foreign_key: { to_table: :users }
      t.references :converted_to_job, foreign_key: { to_table: :inspection_jobs }
      t.references :approved_by, foreign_key: { to_table: :users }
      
      t.text :description, null: false
      t.string :finding_type, null: false
      t.string :priority, default: 'normal'
      t.string :status, default: 'pending'
      t.decimal :estimated_hours, precision: 5, scale: 2
      
      t.text :notes
      t.text :rejection_reason
      t.jsonb :metadata, default: {}
      
      t.datetime :approved_at
      t.datetime :converted_at
      t.datetime :rejected_at
      t.integer :converted_by_id
      
      t.timestamps
    end
    
    add_index :inspection_recommendations, [:inspection_id, :status]
    add_index :inspection_recommendations, [:status, :priority]
  end
end