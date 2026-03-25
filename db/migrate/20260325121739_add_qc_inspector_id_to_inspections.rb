class AddQcInspectorIdToInspections < ActiveRecord::Migration[8.1]
  def change
    add_column :inspections, :qc_inspector_id, :integer
  end
end
