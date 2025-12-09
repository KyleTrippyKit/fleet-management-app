class AddSourceAndEstimatedDeliveryToMaintenances < ActiveRecord::Migration[8.1]
  def change
    add_column :maintenances, :source, :string
    add_column :maintenances, :estimated_delivery, :integer
  end
end
