# db/migrate/[timestamp]_create_quickbooks_integrations.rb
class CreateQuickbooksIntegrations < ActiveRecord::Migration[7.0]
  def change
    create_table :quickbooks_integrations do |t|
      t.string :company_id
      t.string :access_token
      t.string :refresh_token
      t.datetime :token_expires_at
      t.string :realm_id
      t.boolean :connected, default: false
      t.boolean :auto_sync, default: false
      t.datetime :last_sync_at
      t.string :sync_status
      t.text :sync_error
      t.references :user, foreign_key: true
      
      t.timestamps
    end
    
    add_index :quickbooks_integrations, :connected
    add_index :quickbooks_integrations, :company_id, unique: true
  end
end