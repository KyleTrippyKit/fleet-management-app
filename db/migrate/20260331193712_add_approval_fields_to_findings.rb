class AddApprovalFieldsToFindings < ActiveRecord::Migration[8.1]
  def change
    add_column :findings, :approved_by_id, :integer
    add_column :findings, :approved_at, :datetime
  end
end
