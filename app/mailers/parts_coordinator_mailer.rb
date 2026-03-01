class PartsCoordinatorMailer < ApplicationMailer
  def notify(coordinator, inspection)
    @coordinator = coordinator
    @inspection = inspection
    @vehicle = inspection.vehicle
    
    mail(
      to: coordinator.email,
      subject: "Parts Review Required for #{@vehicle.license_plate}"
    )
  end
end