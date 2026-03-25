class AddQcNotesToInspections < ActiveRecord::Migration[8.1]
  def change
    add_column :inspections, :qc_notes, :text
  end
end
