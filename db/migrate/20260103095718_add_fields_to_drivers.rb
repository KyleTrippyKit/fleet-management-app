class AddFieldsToDrivers < ActiveRecord::Migration[8.1]
  def change
    add_column :drivers, :contact_number, :string
    add_column :drivers, :employee_id, :string
    add_column :drivers, :emergency_contact_name, :string
    add_column :drivers, :emergency_contact_phone, :string
  end
end
