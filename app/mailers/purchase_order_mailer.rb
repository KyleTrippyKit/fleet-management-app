class PurchaseOrderMailer < ApplicationMailer
  def acceptance_notification(purchase_order)
    @purchase_order = purchase_order

    recipients = []
    # Notify vendor side (VMCOTT) if possible
    vmcott = Agency.find_by(code: 'VMCOTT')
    if vmcott&.respond_to?(:users)
      recipients.concat(vmcott.users.pluck(:email))
    end

    # Notify agency creator as well
    if purchase_order.created_by&.email
      recipients << purchase_order.created_by.email
    end

    mail(
      to: recipients.uniq.presence || 'no-reply@vmcott.local',
      subject: "PO Accepted / Awaiting Action: #{purchase_order.po_number}"
    )
  end
end