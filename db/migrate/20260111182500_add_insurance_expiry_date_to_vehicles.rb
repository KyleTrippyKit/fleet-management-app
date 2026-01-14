# db/migrate/YYYYMMDDHHMMSS_add_insurance_expiry_date_to_vehicles.rb
class AddInsuranceExpiryDateToVehicles < ActiveRecord::Migration[8.1]
  def change
    add_column :vehicles, :insurance_expiry_date, :date
    
    # Optional: Add index for faster queries if you'll be querying this field often
    add_index :vehicles, :insurance_expiry_date
  end
end