class AddUserIdToPaymentHistories < ActiveRecord::Migration[8.1]
  def change
    add_reference :payment_histories, :user, null: false, foreign_key: true
  end
end
