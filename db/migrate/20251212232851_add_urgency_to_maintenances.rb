class AddUrgencyToMaintenances < ActiveRecord::Migration[8.1]
  def change
    add_column :maintenances, :urgency, :string
  end
end
