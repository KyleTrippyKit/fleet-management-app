# db/migrate/[timestamp]_add_polymorphic_to_vehicles.rb
class AddPolymorphicToVehicles < ActiveRecord::Migration[8.1]
  def change
    add_reference :vehicles, :owner, polymorphic: true
    add_column :invoices, :client_type, :string
    add_column :invoices, :client_id, :bigint
    add_column :quotations, :client_type, :string
    add_column :quotations, :client_id, :bigint
  end
end