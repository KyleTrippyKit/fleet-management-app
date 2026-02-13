class AddDetailsToServiceProviders < ActiveRecord::Migration[8.1]
  def change
    # If these already exist in your table, Rails will error.
    # In that case, tell me what columns exist and I’ll adjust.
    add_column :service_providers, :provider_type, :string, null: false, default: "external_contractor"
    add_column :service_providers, :contact_name, :string
    add_column :service_providers, :phone, :string
    add_column :service_providers, :email, :string
    add_column :service_providers, :address, :string
    add_column :service_providers, :is_active, :boolean, null: false, default: true
    add_column :service_providers, :notes, :text

    add_index :service_providers, :provider_type
    add_index :service_providers, :is_active
    add_index :service_providers, :name
  end
end
