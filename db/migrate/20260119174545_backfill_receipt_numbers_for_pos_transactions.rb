class BackfillReceiptNumbersForPosTransactions < ActiveRecord::Migration[8.1]
  def up
    PosTransaction.find_each do |transaction|
      next if transaction.receipt_number.present?
      
      date_str = transaction.created_at.strftime('%Y%m%d')
      sequence = PosTransaction.where(agency_id: transaction.agency_id)
                              .where("DATE(created_at) = ?", transaction.created_at.to_date)
                              .where("id < ?", transaction.id)
                              .count + 1
      
      agency_code = Agency.find(transaction.agency_id).code || 'AGY'
      receipt_number = "#{agency_code}-#{date_str}-#{format('%05d', sequence)}"
      
      transaction.update_column(:receipt_number, receipt_number)
    end
  end
  
  def down
    # This is irreversible, but you could set all to nil if needed
    # PosTransaction.update_all(receipt_number: nil)
  end
end