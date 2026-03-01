class CreateNotifications < ActiveRecord::Migration[8.1]
  def change
    create_table :notifications do |t|
      t.references :user, null: false, foreign_key: true
      t.string :title, null: false
      t.text :message
      t.references :notifiable, polymorphic: true
      t.string :action_url
      t.datetime :read_at
      t.timestamps
    end
    
    add_index :notifications, [:user_id, :read_at]
    add_index :notifications, :created_at
  end
end