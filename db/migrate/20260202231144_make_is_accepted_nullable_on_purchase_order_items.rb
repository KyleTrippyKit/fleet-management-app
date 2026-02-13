# db/migrate/YYYYMMDDHHMMSS_make_is_accepted_nullable_on_purchase_order_items.rb
class MakeIsAcceptedNullableOnPurchaseOrderItems < ActiveRecord::Migration[7.1]
  def change
    change_column_default :purchase_order_items, :is_accepted, from: true, to: nil
    change_column_null :purchase_order_items, :is_accepted, true
  end
end