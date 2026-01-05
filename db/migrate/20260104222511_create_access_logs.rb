# db/migrate/[timestamp]_create_access_logs.rb
class CreateAccessLogs < ActiveRecord::Migration[8.1]
  def change
    create_table :access_logs do |t|
      t.references :user, null: false, foreign_key: true
      t.references :agency, foreign_key: true
      t.string :resource_type
      t.bigint :resource_id
      t.string :action, null: false
      t.string :outcome, null: false
      t.jsonb :details
      t.string :ip_address
      t.string :user_agent
      t.datetime :accessed_at
      t.timestamps
      
      t.index [:user_id, :accessed_at]
      t.index [:agency_id, :accessed_at]
      t.index [:resource_type, :resource_id, :accessed_at]
      t.index [:action, :accessed_at]
    end
  end
end