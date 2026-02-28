class CreateReceptionLogs < ActiveRecord::Migration[8.1]
  def change
    create_table :reception_logs do |t|
      # Basic fields that are commonly needed for reception logs
      t.string :visitor_name, null: false
      t.string :company
      t.string :purpose
      t.string :person_to_visit
      t.string :badge_number
      t.datetime :check_in_time, null: false
      t.datetime :check_out_time
      t.string :status, default: 'checked_in'
      t.text :notes
      
      # Foreign keys
      t.bigint :user_id  # The receptionist who logged this
      t.bigint :agency_id
      t.bigint :vehicle_id  # If they came with a vehicle
      
      # Contact information
      t.string :contact_number
      t.string :email
      
      # Identification
      t.string :id_type
      t.string :id_number
      
      # Additional metadata
      t.jsonb :metadata, default: {}
      
      t.timestamps
    end
    
    # Add indexes for common queries
    add_index :reception_logs, :check_in_time
    add_index :reception_logs, :status
    add_index :reception_logs, :user_id
    add_index :reception_logs, :agency_id
    add_index :reception_logs, :visitor_name
    add_index :reception_logs, [:check_in_time, :status]
  end
end