# app/mailers/inventory_manager_mailer.rb
# Renamed from parts_coordinator_mailer to inventory_manager_mailer

class InventoryManagerMailer < ApplicationMailer
  def notify(inventory_manager, inspection)
    @inventory_manager = inventory_manager
    @inspection = inspection
    @vehicle = inspection.vehicle
    
    mail(
      to: inventory_manager.email,
      subject: "Parts Review Required for #{@vehicle.license_plate}"
    )
  end
end