class CreateAlerts < ActiveRecord::Migration[8.1]
  def change
    create_table :alerts do |t|
      # Basic info
      t.string :title, null: false
      t.text :description
      
      # Alert categorization
      t.string :alert_type, null: false
      t.string :severity, null: false
      t.string :priority, null: false
      t.string :status, null: false, default: 'active'
      
      # Associated records
      t.references :vehicle, foreign_key: true
      t.references :driver, foreign_key: true
      t.references :agency, foreign_key: true
      
      # Location and timing
      t.string :location
      t.string :coordinates
      t.datetime :incident_time
      t.datetime :estimated_resolution_time
      
      # Response info
      t.text :actions_taken
      t.text :required_actions
      t.string :assigned_to
      t.string :created_by
      
      # Additional info
      t.text :notes
      t.jsonb :metadata, default: {}
      
      # Timestamps
      t.timestamps
      
      # Indexes for performance
      t.index [:status, :severity]
      t.index [:vehicle_id, :created_at]
      t.index [:agency_id, :created_at]
      t.index [:severity, :priority]
    end
  end
end
