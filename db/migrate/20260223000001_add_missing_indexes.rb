# db/migrate/20260223000001_add_missing_indexes.rb
class AddMissingIndexes < ActiveRecord::Migration[8.1]
  def change
    add_index :purchase_orders, [:vendor, :status]
    add_index :purchase_orders, :acceptance_status
    add_index :purchase_orders, :vmcott_status
    add_index :invoices, [:status, :due_date]
    add_index :alerts, [:status, :severity, :priority]
  end
end