class AddStatusAndReferencesToMaintenances < ActiveRecord::Migration[8.1]
  def change
    # Add 'details' column only if it doesn't exist
    unless column_exists?(:maintenances, :details)
      add_column :maintenances, :details, :string
    end

    # Add 'status' column only if it doesn't exist
    unless column_exists?(:maintenances, :status)
      add_column :maintenances, :status, :string
    end

    # Add vehicle reference only if it doesn't exist
    unless column_exists?(:maintenances, :vehicle_id)
      add_reference :maintenances, :vehicle, foreign_key: true
    end
  end
end
