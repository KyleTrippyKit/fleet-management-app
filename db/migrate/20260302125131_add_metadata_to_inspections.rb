# db/migrate/20260302130000_add_metadata_to_inspections.rb
class AddMetadataToInspections < ActiveRecord::Migration[8.1]
  def change
    add_column :inspections, :metadata, :jsonb, default: {}
    add_index :inspections, :metadata, using: :gin
  end
end