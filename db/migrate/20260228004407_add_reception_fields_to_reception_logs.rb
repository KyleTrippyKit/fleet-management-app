class AddReceptionFieldsToReceptionLogs < ActiveRecord::Migration[8.1]
  def change
    change_table :reception_logs do |t|
      # Add missing columns from your model
      t.string :driver_name
      t.bigint :purchase_order_id
      t.datetime :inspected_at
      t.bigint :inspector_id
      t.datetime :received_at  # Adding this too since your model uses it
      
      # Add indexes for the new columns
      t.index :purchase_order_id
      t.index :inspector_id
      t.index :inspected_at
      t.index :received_at
    end

    # Add foreign keys (if the tables exist)
    add_foreign_key :reception_logs, :purchase_orders, column: :purchase_order_id, if_not_exists: true
    add_foreign_key :reception_logs, :users, column: :inspector_id, if_not_exists: true
  end
end