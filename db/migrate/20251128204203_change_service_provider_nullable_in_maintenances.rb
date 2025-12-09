class ChangeServiceProviderNullableInMaintenances < ActiveRecord::Migration[7.0]
  def change
    change_column_null :maintenances, :service_provider_id, true
  end
end
