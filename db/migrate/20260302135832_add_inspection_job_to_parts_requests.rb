# db/migrate/202603021406xx_add_inspection_job_to_parts_requests.rb
class AddInspectionJobToPartsRequests < ActiveRecord::Migration[8.1]
  def change
    add_reference :parts_requests, :inspection_job, foreign_key: true
  end
end