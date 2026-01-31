# db/migrate/XXXXXXXXXXXXXX_fix_unique_index_on_payables_purchase_order_id.rb
class FixUniqueIndexOnPayablesPurchaseOrderId < ActiveRecord::Migration[8.1]
  def up
    # Remove the existing (non-unique) index if present
    if index_exists?(:payables, :purchase_order_id, name: "index_payables_on_purchase_order_id")
      remove_index :payables, name: "index_payables_on_purchase_order_id"
    end

    # Add it back as UNIQUE
    add_index :payables, :purchase_order_id, unique: true, name: "index_payables_on_purchase_order_id"
  end

  def down
    remove_index :payables, name: "index_payables_on_purchase_order_id"
    add_index :payables, :purchase_order_id, unique: false, name: "index_payables_on_purchase_order_id"
  end
end
