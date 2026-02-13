class AddPurchaseOrderToVendorQuotations < ActiveRecord::Migration[8.1]
  def change
    add_reference :vendor_quotations,
                  :purchase_order,
                  null: true,          # ✅ allow existing rows
                  foreign_key: true
  end
end
