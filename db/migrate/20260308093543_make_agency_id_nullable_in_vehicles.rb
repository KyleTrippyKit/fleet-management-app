class MakeAgencyIdNullableInVehicles < ActiveRecord::Migration[8.1]
  def change
    change_column_null :vehicles, :agency_id, true
  end
end