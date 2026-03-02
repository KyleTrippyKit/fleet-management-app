class AddFieldsToPartsRequests < ActiveRecord::Migration[8.1]
  def change
    add_column :parts_requests, :processed_by, :integer
    add_column :parts_requests, :processed_at, :datetime
    add_column :parts_requests, :sent_to_billing_at, :datetime
    # REMOVE these lines since they already exist:
    # add_column :parts_requests, :inspection_job_id, :integer
    # add_index :parts_requests, :inspection_job_id
  end
end