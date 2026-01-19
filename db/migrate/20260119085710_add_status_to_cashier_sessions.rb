class AddStatusToCashierSessions < ActiveRecord::Migration[8.1]
  def change
    add_column :cashier_sessions, :status, :integer
  end
end
