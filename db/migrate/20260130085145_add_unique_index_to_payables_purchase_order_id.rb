# db/migrate/20260130085145_add_unique_index_to_payables_purchase_order_id.rb
class AddUniqueIndexToPayablesPurchaseOrderId < ActiveRecord::Migration[8.1]
  def change
    return if index_exists?(:payables, :purchase_order_id, name: "index_payables_on_purchase_order_id")

    add_index :payables, :purchase_order_id, unique: true
  end
end
