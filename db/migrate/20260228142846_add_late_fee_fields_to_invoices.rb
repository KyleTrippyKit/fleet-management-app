class AddLateFeeFieldsToInvoices < ActiveRecord::Migration[8.1]
  def change
    add_column :invoices, :late_fee_applied, :boolean
    add_column :invoices, :late_fee_amount, :decimal
    add_column :invoices, :last_reminder_sent_at, :datetime
  end
end
