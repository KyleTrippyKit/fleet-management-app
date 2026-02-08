class AddAgencyToServiceProviders < ActiveRecord::Migration[8.1]
  def change
    add_reference :service_providers, :agency, foreign_key: true
  end
end