# frozen_string_literal: true

class AdjustServiceProvidersForInternalWorkshops < ActiveRecord::Migration[8.1]
  def up
    # Make new service_providers default to internal workshops
    change_column_default :service_providers,
                          :provider_type,
                          from: "external_contractor",
                          to: "internal_workshop"

    # Helpful index for VMCOTT queries (safe: NOT unique)
    unless index_exists?(:service_providers, [:agency_id, :name], name: "index_service_providers_on_agency_id_and_name")
      add_index :service_providers, [:agency_id, :name], name: "index_service_providers_on_agency_id_and_name"
    end
  end

  def down
    change_column_default :service_providers,
                          :provider_type,
                          from: "internal_workshop",
                          to: "external_contractor"

    if index_exists?(:service_providers, [:agency_id, :name], name: "index_service_providers_on_agency_id_and_name")
      remove_index :service_providers, name: "index_service_providers_on_agency_id_and_name"
    end
  end
end
