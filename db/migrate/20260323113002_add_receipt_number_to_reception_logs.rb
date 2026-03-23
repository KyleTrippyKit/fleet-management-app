class AddReceiptNumberToReceptionLogs < ActiveRecord::Migration[8.1]
  def change
    add_column :reception_logs, :receipt_number, :string
  end
end
