# db/migrate/XXXXXXXXXXXXXX_add_custom_part_name_to_vendor_rfq_items.rb
class AddCustomPartNameToVendorRfqItems < ActiveRecord::Migration[8.1]
  def change
    add_column :vendor_rfq_items, :custom_part_name, :string
  end
end