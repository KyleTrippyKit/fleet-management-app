class FixMaintenanceNilDates < ActiveRecord::Migration[8.1]
  def up
    # Update nil dates with default values
    puts "Fixing #{Maintenance.where(date: nil).count} maintenance records with nil dates..."
    
    Maintenance.where(date: nil).find_each do |maintenance|
      puts "  - Fixing maintenance ##{maintenance.id}: date = #{Date.today}"
      maintenance.update(date: Date.today)
    end
    
    puts "Fixed all nil dates!"
  end

  def down
    # This migration only fixes data, no need to revert
    puts "Data fix migration - nothing to revert"
  end
end