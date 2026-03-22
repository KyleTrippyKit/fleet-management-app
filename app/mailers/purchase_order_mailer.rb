# app/mailers/purchase_order_mailer.rb
class PurchaseOrderMailer < ApplicationMailer
  default from: 'procurement@vmcott.com'

  def po_created(purchase_order)
    @purchase_order = purchase_order
    @vendor = purchase_order.vendor
    @po_number = purchase_order.po_number
    @items = purchase_order.purchase_order_items
    @total = purchase_order.amount
    @vehicle = purchase_order.vehicle
    
    supplier = Supplier.find_by(name: purchase_order.vendor)
    vendor_email = supplier&.email
    
    if vendor_email.present?
      mail(
        to: vendor_email,
        subject: "Purchase Order ##{@po_number} Created - VMCOTT"
      )
    end
  end

  # Add this method for stock received notification
  def stock_received(purchase_order, recipients)
    @purchase_order = purchase_order
    @po_number = purchase_order.po_number
    @items = purchase_order.purchase_order_items
    @vendor = purchase_order.vendor
    @received_at = purchase_order.received_at || Time.current
    
    mail(
      to: recipients,
      subject: "Stock Received for PO ##{@po_number} - Inventory Update Required",
      bcc: 'procurement@vmcott.com'
    )
  end

  def parts_available(purchase_order, recipients)
    @purchase_order = purchase_order
    @po_number = purchase_order.po_number
    @items = purchase_order.purchase_order_items
    @vehicle = purchase_order.vehicle
    
    mail(
      to: recipients,
      subject: "Parts Available for PO ##{@po_number} - Ready for Workshop",
      bcc: 'procurement@vmcott.com'
    )
  end

  def ready_for_payment(purchase_order, recipients)
    @purchase_order = purchase_order
    @po_number = purchase_order.po_number
    @amount = purchase_order.amount
    @vendor = purchase_order.vendor
    
    mail(
      to: recipients,
      subject: "PO ##{@po_number} Ready for Payment",
      bcc: 'procurement@vmcott.com'
    )
  end

  def po_approved(purchase_order)
    @purchase_order = purchase_order
    @vendor = purchase_order.vendor
    @po_number = purchase_order.po_number
    @items = purchase_order.purchase_order_items
    @total = purchase_order.amount
    @vehicle = purchase_order.vehicle
    
    supplier = Supplier.find_by(name: purchase_order.vendor)
    vendor_email = supplier&.email
    
    if vendor_email.present?
      mail(
        to: vendor_email,
        subject: "Purchase Order ##{@po_number} Approved - VMCOTT"
      )
    end
  end

  def po_paid(purchase_order)
    @purchase_order = purchase_order
    @vendor = purchase_order.vendor
    @po_number = purchase_order.po_number
    @amount = purchase_order.amount
    @payment_method = purchase_order.payment_method
    @payment_reference = purchase_order.payment_reference
    
    supplier = Supplier.find_by(name: purchase_order.vendor)
    vendor_email = supplier&.email
    
    if vendor_email.present?
      mail(
        to: vendor_email,
        subject: "Payment Confirmed for Purchase Order ##{@po_number} - VMCOTT"
      )
    end
  end

  def po_rejected(purchase_order)
    @purchase_order = purchase_order
    @vendor = purchase_order.vendor
    @po_number = purchase_order.po_number
    @reason = purchase_order.rejection_reason
    
    supplier = Supplier.find_by(name: purchase_order.vendor)
    vendor_email = supplier&.email
    
    if vendor_email.present?
      mail(
        to: vendor_email,
        subject: "Purchase Order ##{@po_number} Requires Revision - VMCOTT"
      )
    end
  end

  def po_delivered(purchase_order)
    @purchase_order = purchase_order
    @vendor = purchase_order.vendor
    @po_number = purchase_order.po_number
    @vehicle = purchase_order.vehicle
    
    supplier = Supplier.find_by(name: purchase_order.vendor)
    vendor_email = supplier&.email
    
    if vendor_email.present?
      mail(
        to: vendor_email,
        subject: "Delivery Confirmation for Purchase Order ##{@po_number} - VMCOTT"
      )
    end
  end
end