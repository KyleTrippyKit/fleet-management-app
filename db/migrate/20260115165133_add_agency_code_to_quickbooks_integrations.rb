class AddAgencyCodeToQuickbooksIntegrations < ActiveRecord::Migration[8.1]
  def change
    add_column :quickbooks_integrations, :agency_code, :string
  end
end
