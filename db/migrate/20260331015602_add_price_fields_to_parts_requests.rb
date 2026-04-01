class AddPriceFieldsToPartsRequests < ActiveRecord::Migration[8.1]
  def change
    add_column :parts_requests, :unit_price, :decimal, precision: 10, scale: 2
    add_column :parts_requests, :customer_price, :decimal, precision: 10, scale: 2
    add_column :parts_requests, :total_price, :decimal, precision: 10, scale: 2
    add_column :parts_requests, :ordered_at, :datetime
  end
end