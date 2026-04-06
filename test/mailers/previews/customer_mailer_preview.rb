# Preview all emails at http://localhost:3000/rails/mailers/customer_mailer
class CustomerMailerPreview < ActionMailer::Preview
  # Preview this email at http://localhost:3000/rails/mailers/customer_mailer/vehicle_ready
  def vehicle_ready
    CustomerMailer.vehicle_ready
  end

  # Preview this email at http://localhost:3000/rails/mailers/customer_mailer/quotation_ready
  def quotation_ready
    CustomerMailer.quotation_ready
  end

  # Preview this email at http://localhost:3000/rails/mailers/customer_mailer/status_update
  def status_update
    CustomerMailer.status_update
  end
end
