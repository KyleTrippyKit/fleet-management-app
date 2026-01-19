class AddPaymentTransactionTypeToPaymentHistories < ActiveRecord::Migration[8.1]
  def change
    add_column :payment_histories, :payment_transaction_type, :string
  end
end
