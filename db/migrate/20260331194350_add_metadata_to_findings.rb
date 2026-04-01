class AddMetadataToFindings < ActiveRecord::Migration[8.1]
  def change
    add_column :findings, :metadata, :jsonb
  end
end
