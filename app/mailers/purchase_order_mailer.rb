# app/mailers/purchase_order_mailer.rb
class PurchaseOrderMailer < ApplicationMailer
  default from: 'noreply@vmcott.com'

  def po_created(purchase_order)
    @purchase_order = purchase_order
    @agency = purchase_order.agency
    @vehicle = purchase_order.vehicle
    
    # Find VMCOTT users to notify
    vmcott = Agency.find_by(code: 'VMCOTT')
    recipients = []
    
    if vmcott&.respond_to?(:users)
      recipients.concat(vmcott.users.where(notify_on_po_created: true).pluck(:email))
    end
    
    mail(
      to: recipients.presence || 'vmcott@example.com',
      subject: "New Purchase Order from #{@agency&.name || 'Agency'}: #{purchase_order.po_number}"
    )
  end

  def po_accepted(purchase_order)
    @purchase_order = purchase_order
    @agency = purchase_order.agency
    @vehicle = purchase_order.vehicle
    
    # Notify the person who created the PO
    if purchase_order.created_by&.email
      mail(
        to: purchase_order.created_by.email,
        subject: "PO #{purchase_order.po_number} Accepted - Work Started"
      )
    end
  end

  def po_rejected(purchase_order)
    @purchase_order = purchase_order
    @agency = purchase_order.agency
    @vehicle = purchase_order.vehicle
    @rejection_reason = purchase_order.rejection_reason
    
    if purchase_order.created_by&.email
      mail(
        to: purchase_order.created_by.email,
        subject: "PO #{purchase_order.po_number} Rejected"
      )
    end
  end

  def po_delivered(purchase_order)
    @purchase_order = purchase_order
    @agency = purchase_order.agency
    @vehicle = purchase_order.vehicle
    
    if purchase_order.created_by&.email
      mail(
        to: purchase_order.created_by.email,
        subject: "PO #{purchase_order.po_number} Delivered - Ready for Pickup"
      )
    end
  end

  def po_paid(purchase_order)
    @purchase_order = purchase_order
    @agency = purchase_order.agency
    @vehicle = purchase_order.vehicle
    
    # Notify VMCOTT that payment is complete
    vmcott = Agency.find_by(code: 'VMCOTT')
    recipients = []
    
    if vmcott&.respond_to?(:users)
      recipients.concat(vmcott.users.where(notify_on_po_paid: true).pluck(:email))
    end
    
    mail(
      to: recipients.presence || 'finance@vmcott.com',
      subject: "PO #{purchase_order.po_number} Paid - Transaction Complete"
    ) if recipients.any?
  end
end