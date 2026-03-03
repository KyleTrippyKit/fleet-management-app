# db/migrate/YYYYMMDDHHMMSS_make_part_id_nullable_in_vendor_rfq_items.rb
class MakePartIdNullableInVendorRfqItems < ActiveRecord::Migration[8.1]
  def change
    change_column_null :vendor_rfq_items, :part_id, true
  end
end