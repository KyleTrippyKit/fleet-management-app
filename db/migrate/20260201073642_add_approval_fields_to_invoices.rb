class AddApprovalFieldsToInvoices < ActiveRecord::Migration[8.1]
  def change
    add_column :invoices, :approved_by_id, :integer
    add_column :invoices, :approved_at, :datetime

    add_index :invoices, :approved_by_id
    add_foreign_key :invoices, :users, column: :approved_by_id
  end
end
