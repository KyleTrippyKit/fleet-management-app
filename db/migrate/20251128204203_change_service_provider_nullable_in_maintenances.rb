class ChangeServiceProviderNullableInMaintenances < ActiveRecord::Migration[8.1]
  def change
    change_column_null :maintenances, :service_provider_id, true
  end
end
