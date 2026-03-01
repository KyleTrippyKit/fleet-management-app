class AddCustomPartNameToPartsRequests < ActiveRecord::Migration[8.1]
  def change
    add_column :parts_requests, :custom_part_name, :string
  end
end
