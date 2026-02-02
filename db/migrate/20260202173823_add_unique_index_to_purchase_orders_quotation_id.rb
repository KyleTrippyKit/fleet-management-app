class AddUniqueIndexToPurchaseOrdersQuotationId < ActiveRecord::Migration[8.1]
  def up
    # Drop the existing non-unique index (same name)
    if index_exists?(:purchase_orders, :quotation_id, name: "index_purchase_orders_on_quotation_id")
      remove_index :purchase_orders, name: "index_purchase_orders_on_quotation_id"
    end

    # Re-create as UNIQUE (same name)
    add_index :purchase_orders, :quotation_id,
              unique: true,
              name: "index_purchase_orders_on_quotation_id"
  end

  def down
    remove_index :purchase_orders, name: "index_purchase_orders_on_quotation_id" rescue nil

    add_index :purchase_orders, :quotation_id,
              name: "index_purchase_orders_on_quotation_id"
  end
end
