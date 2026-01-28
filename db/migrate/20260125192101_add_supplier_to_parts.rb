class AddSupplierToParts < ActiveRecord::Migration[8.1]
  def change
    add_reference :parts, :supplier, null: false, foreign_key: true
  end
end
