class AddRequestedByIdToPartsRequests < ActiveRecord::Migration[8.1]
  def change
    add_column :parts_requests, :requested_by_id, :integer
  end
end
