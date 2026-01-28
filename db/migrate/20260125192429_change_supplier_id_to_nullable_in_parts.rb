class ChangeSupplierIdToNullableInParts < ActiveRecord::Migration[8.1]
  def change
    change_column_null :parts, :supplier_id, true
  end
end