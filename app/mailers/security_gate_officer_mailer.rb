# app/mailers/security_gate_officer_mailer.rb
# Renamed from receptionist_mailer to security_gate_officer_mailer

class SecurityGateOfficerMailer < ApplicationMailer
  def vehicle_arrived(officer, reception_log)
    @officer = officer
    @reception_log = reception_log
    @vehicle = reception_log.vehicle
    @condition_report = reception_log.condition_report
    
    mail(
      to: officer.email,
      subject: "Vehicle #{@vehicle.license_plate} Arrived"
    )
  end
  
  def condition_report_submitted(officer, condition_report)
    @officer = officer
    @condition_report = condition_report
    @vehicle = condition_report.vehicle
    
    mail(
      to: officer.email,
      subject: "Condition Report Completed for #{@vehicle.license_plate}"
    )
  end
end