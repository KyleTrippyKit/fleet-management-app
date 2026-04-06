class AddReceptionLogToInspections < ActiveRecord::Migration[7.0]
  def change
    add_reference :inspections, :reception_log, foreign_key: true
  end
end