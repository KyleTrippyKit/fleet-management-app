class CreateQuickbooksSettings < ActiveRecord::Migration[8.1]
  def change
    create_table :quickbooks_settings do |t|
      t.boolean :connected
      t.boolean :auto_sync
      t.string :company_id
      t.text :access_token
      t.text :refresh_token
      t.datetime :last_sync_at
      t.references :user, null: false, foreign_key: true

      t.timestamps
    end
  end
end
