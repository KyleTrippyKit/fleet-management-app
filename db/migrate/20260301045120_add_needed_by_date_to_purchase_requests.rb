# db/migrate/xxxxxx_add_needed_by_date_to_purchase_requests.rb
class AddNeededByDateToPurchaseRequests < ActiveRecord::Migration[8.1]
  def change
    add_column :purchase_requests, :needed_by_date, :date
  end
end