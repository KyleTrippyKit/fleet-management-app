# db/migrate/[timestamp]_create_clients.rb
class CreateClients < ActiveRecord::Migration[8.1]
  def change
    create_table :clients do |t|
      t.string :name, null: false
      t.string :email
      t.string :phone
      t.string :address
      t.integer :client_type, default: 0
      t.integer :payment_terms, default: 0
      t.decimal :credit_limit, precision: 10, scale: 2
      t.boolean :is_active, default: true
      t.references :agency, foreign_key: true
      t.timestamps
    end
  end
end