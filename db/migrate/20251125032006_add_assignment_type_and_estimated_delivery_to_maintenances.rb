class AddAssignmentTypeAndEstimatedDeliveryToMaintenances < ActiveRecord::Migration[8.1]
  def change
    add_column :maintenances, :assignment_type, :string
    add_column :maintenances, :estimated_delivery_date, :date
  end
end
