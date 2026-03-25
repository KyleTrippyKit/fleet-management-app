class AddInspectionIdToQuotations < ActiveRecord::Migration[8.1]
  def change
    add_column :quotations, :inspection_id, :bigint
    add_index :quotations, :inspection_id
  end
end
