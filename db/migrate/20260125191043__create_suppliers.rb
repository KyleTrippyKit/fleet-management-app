# db/migrate/20260126000000_create_suppliers.rb
class CreateSuppliers < ActiveRecord::Migration[8.1]
  def change
    create_table :suppliers do |t|
      t.string :name, null: false
      t.string :contact_person
      t.string :phone
      t.string :email
      t.string :address
      t.text :notes
      t.string :payment_terms
      t.boolean :is_active, default: true
      
      t.timestamps
      
      t.index :name, unique: true
      t.index :is_active
    end
  end
end