class AddReceiptNumberToTransactions < ActiveRecord::Migration[8.1]
  def change
    add_column :pos_transactions, :receipt_number, :string
    
    # Add index for better query performance (optional but recommended)
    add_index :pos_transactions, :receipt_number
    
    # Or if receipt numbers should be unique:
    # add_index :pos_transactions, :receipt_number, unique: true
  end
end