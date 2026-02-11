# frozen_string_literal: true

class SetAlertsAgencyIdNotNull < ActiveRecord::Migration[8.1]
  def change
    change_column_null :alerts, :agency_id, false

    # Only add the index if it doesn't already exist
    add_index :alerts, :agency_id unless index_exists?(:alerts, :agency_id)
  end
end
