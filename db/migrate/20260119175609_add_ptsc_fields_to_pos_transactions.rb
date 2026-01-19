class AddPtscFieldsToPosTransactions < ActiveRecord::Migration[8.1]
  def change
    add_column :pos_transactions, :route_code, :string
    add_column :pos_transactions, :ticket_type, :string
    add_column :pos_transactions, :fare_class, :string, default: 'adult'
    add_column :pos_transactions, :passenger_count, :integer, default: 1
    add_column :pos_transactions, :unit_fare, :decimal, precision: 10, scale: 2
    add_column :pos_transactions, :origin_stop, :string
    add_column :pos_transactions, :destination_stop, :string
    add_column :pos_transactions, :is_return_trip, :boolean, default: false
    add_column :pos_transactions, :mobile_money_total, :decimal, precision: 10, scale: 2, default: 0.0
    add_column :pos_transactions, :bank_transfer_total, :decimal, precision: 10, scale: 2, default: 0.0
    
    # Add indexes for better performance
    add_index :pos_transactions, :route_code
    add_index :pos_transactions, :fare_class
    add_index :pos_transactions, :ticket_type
    add_index :pos_transactions, [:agency_id, :receipt_number], unique: true
    
    # Add fare rule table for PTSC
    create_table :fare_rules do |t|
      t.references :agency, null: false
      t.string :route_code, null: false
      t.string :fare_class, null: false
      t.decimal :amount, precision: 10, scale: 2, null: false
      t.decimal :child_amount, precision: 10, scale: 2
      t.decimal :student_amount, precision: 10, scale: 2
      t.decimal :senior_amount, precision: 10, scale: 2
      t.boolean :is_active, default: true
      t.date :effective_from
      t.date :effective_to
      t.text :notes
      
      t.timestamps
      
      t.index [:agency_id, :route_code, :fare_class], unique: true, name: 'index_fare_rules_on_agency_route_class'
    end
    
    # Add route table
    create_table :routes do |t|
      t.references :agency, null: false
      t.string :route_code, null: false
      t.string :name, null: false
      t.string :description
      t.string :start_point
      t.string :end_point
      t.decimal :distance_km, precision: 10, scale: 2
      t.integer :estimated_duration_minutes
      t.jsonb :stops
      t.boolean :is_active, default: true
      
      t.timestamps
      
      t.index [:agency_id, :route_code], unique: true
    end
    
    # Add PTSC-specific payment methods to cashier_sessions
    add_column :cashier_sessions, :mobile_money_total, :decimal, precision: 10, scale: 2, default: 0.0
    add_column :cashier_sessions, :bank_transfer_total, :decimal, precision: 10, scale: 2, default: 0.0
  end
end