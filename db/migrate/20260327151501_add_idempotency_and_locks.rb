# db/migrate/20260341000005_add_idempotency_and_locks.rb
class AddIdempotencyAndLocks < ActiveRecord::Migration[8.1]
  def change
    add_column :payments, :idempotency_key, :string unless column_exists?(:payments, :idempotency_key)
    add_column :invoices, :idempotency_key, :string unless column_exists?(:invoices, :idempotency_key)
    add_column :quotations, :idempotency_key, :string unless column_exists?(:quotations, :idempotency_key)

    add_index :payments, :idempotency_key, unique: true, where: "idempotency_key IS NOT NULL"
    add_index :invoices, :idempotency_key, unique: true, where: "idempotency_key IS NOT NULL"
    add_index :quotations, :idempotency_key, unique: true, where: "idempotency_key IS NOT NULL"

    add_column :parts, :quantity_reserved, :integer, default: 0 unless column_exists?(:parts, :quantity_reserved)

    add_check_constraint :parts, 
      "quantity_reserved >= 0",
      name: "quantity_reserved_positive"
  end
end