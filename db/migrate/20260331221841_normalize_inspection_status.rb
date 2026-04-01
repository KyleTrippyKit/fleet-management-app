class NormalizeInspectionStatus < ActiveRecord::Migration[8.1]
  def up
    change_column :inspections, :status, :string, default: "received"

    execute <<-SQL
      UPDATE inspections
      SET status = 'received'
      WHERE status IS NULL
    SQL
  end

  def down
    change_column :inspections, :status, :integer
  end
end