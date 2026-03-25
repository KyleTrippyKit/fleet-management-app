class AddInspectionIdToInvoices < ActiveRecord::Migration[8.1]
  def change
    add_column :invoices, :inspection_id, :integer
    add_index :invoices, :inspection_id
  end
end
