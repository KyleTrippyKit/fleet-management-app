class CreateVehicleDocuments < ActiveRecord::Migration[8.1]
  def change
    create_table :vehicle_documents do |t|
      t.references :vehicle, null: false, foreign_key: true
      t.string :doc_type
      t.string :file
      t.date :expires_on

      t.timestamps
    end
  end
end
