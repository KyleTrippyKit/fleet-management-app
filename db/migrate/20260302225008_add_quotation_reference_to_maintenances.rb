class AddQuotationReferenceToMaintenances < ActiveRecord::Migration[8.1]
  def change
    add_reference :maintenances, :quotation, foreign_key: true
  end
end