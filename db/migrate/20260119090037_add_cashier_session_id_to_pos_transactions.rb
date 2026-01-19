# db/migrate/[timestamp]_add_cashier_session_id_to_pos_transactions.rb
class AddCashierSessionIdToPosTransactions < ActiveRecord::Migration[8.1]
  def change
    add_reference :pos_transactions, :cashier_session, foreign_key: true
  end
end