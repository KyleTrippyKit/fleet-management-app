# db/migrate/20250120_create_agency_settings.rb
class CreateAgencySettings < ActiveRecord::Migration[8.1]
  def change
    create_table :agency_settings do |t|
      t.bigint :agency_id, null: false
      t.string :setting_key, null: false
      t.text :setting_value
      t.string :data_type, default: "string"
      t.text :description

      t.timestamps

      t.index [:agency_id, :setting_key], name: "index_agency_settings_on_agency_id_and_setting_key", unique: true
      t.index [:agency_id], name: "index_agency_settings_on_agency_id"
    end

    # Add foreign key constraint
    add_foreign_key :agency_settings, :agencies
  end
end