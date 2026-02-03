class InventoryMailer < ApplicationMailer
  def low_stock_alert(part)
    @part = part

    vmcott = Agency.find_by(code: "VMCOTT")
    recipients =
      if vmcott&.users
        vmcott.users.where.not(email: [nil, ""]).pluck(:email)
      else
        []
      end

    mail(
      to: recipients.presence || "no-reply@vmcott.local",
      subject: "Low Stock Alert: #{@part.name} (#{@part.current_stock})"
    )
  end
end
