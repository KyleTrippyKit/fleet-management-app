class AddCompoundTrackingToVehicles < ActiveRecord::Migration[8.1]
  def change
    add_column :vehicles, :in_compound, :boolean, default: false, null: false

    add_column :vehicles, :checked_in_at,  :datetime
    add_column :vehicles, :checked_out_at, :datetime

    add_column :vehicles, :checked_in_by_id,  :bigint
    add_column :vehicles, :checked_out_by_id, :bigint

    add_index :vehicles, :in_compound
    add_index :vehicles, :checked_in_by_id
    add_index :vehicles, :checked_out_by_id
  end
end
