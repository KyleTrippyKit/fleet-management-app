class CreatePayments < ActiveRecord::Migration[8.1]
  def change
    create_table :payments do |t|
      t.references :inspection, null: false, foreign_key: true
      t.decimal :amount
      t.string :payment_method
      t.string :transaction_id
      t.string :status
      t.datetime :paid_at

      t.timestamps
    end
  end
end
