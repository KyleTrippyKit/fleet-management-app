# db/migrate/XXXXXXXXXXXXXX_create_ledger_entries.rb
class CreateLedgerEntries < ActiveRecord::Migration[8.1]
  def change
    create_table :ledger_entries do |t|
      t.references :agency, null: false, foreign_key: true
      t.references :vehicle, null: false, foreign_key: true
      t.references :invoice, null: false, foreign_key: true

      t.date :entry_date, null: false

      t.string :account_code, null: false
      t.string :account_name, null: false

      t.decimal :debit,  precision: 12, scale: 2, default: 0, null: false
      t.decimal :credit, precision: 12, scale: 2, default: 0, null: false

      t.string :memo
      t.bigint :posted_by_id

      t.timestamps
    end

    add_index :ledger_entries, [:invoice_id, :account_code]
    add_foreign_key :ledger_entries, :users, column: :posted_by_id
  end
end
