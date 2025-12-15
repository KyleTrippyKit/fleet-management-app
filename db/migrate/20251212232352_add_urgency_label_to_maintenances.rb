class AddUrgencyLabelToMaintenances < ActiveRecord::Migration[8.1]
  def change
    add_column :maintenances, :urgency_label, :string
  end
end
