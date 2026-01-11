class AddAgencyToUsers < ActiveRecord::Migration[8.1]
  def change
    unless column_exists?(:users, :agency_id)
      add_reference :users, :agency, foreign_key: true
    end
  end
end
