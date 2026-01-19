class CreateCashierSessions < ActiveRecord::Migration[8.1]
  def change
    create_table :cashier_sessions do |t|
      t.timestamps
    end
  end
end
