class AddUserReferencesToInvoices < ActiveRecord::Migration[8.1]
  def change
    add_column :invoices, :created_by_id, :integer
    add_column :invoices, :received_by_id, :integer
    add_column :invoices, :paid_by_id, :integer
    add_column :invoices, :disputed_by_id, :integer
    add_column :invoices, :received_at, :datetime
    add_column :invoices, :paid_at, :datetime
    add_column :invoices, :disputed_at, :datetime
  end
end
