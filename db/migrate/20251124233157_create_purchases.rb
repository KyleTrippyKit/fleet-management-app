class CreatePurchases < ActiveRecord::Migration[8.1]
  def change
    create_table :purchases do |t|
      t.references :part, null: false, foreign_key: true
      t.integer :quantity
      t.string :supplier
      t.date :eta
      t.string :status

      t.timestamps
    end
  end
end
