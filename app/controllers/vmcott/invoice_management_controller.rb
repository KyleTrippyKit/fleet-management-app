# app/controllers/vmcott/invoice_management_controller.rb
module Vmcott
  class InvoiceManagementController < ApplicationController
    before_action :authenticate_user!
    before_action :require_vmcott_user
    before_action :set_quotation, only: [:create_invoice_from_quotation]

    def create_invoice_from_quotation
      # Check if invoice already exists
      if @quotation.invoice.present?
        redirect_to invoice_path(@quotation.invoice), 
                    notice: 'Invoice already exists for this quotation.'
        return
      end

      # Create invoice
      @invoice = Invoice.new(
        quotation_id: @quotation.id,
        purchase_order_id: @quotation.purchase_order_id,
        vehicle_id: @quotation.vehicle_id,
        vendor: 'VMCOTT',
        amount: @quotation.amount,
        invoice_date: Date.today,
        due_date: Date.today + 30.days,
        invoice_number: generate_invoice_number,
        status: 'pending',
        category: 'maintenance',
        notes: "Invoice generated from quotation #{@quotation.quote_number}"
      )

      if @invoice.save
        # Update quotation status
        @quotation.update(invoiced: true)
        
        # Create activity log
        ActivityLog.create!(
          user: current_user,
          action: 'invoice_created',
          description: "Created invoice #{@invoice.invoice_number} from quotation #{@quotation.quote_number}",
          record: @invoice
        )
        
        # Send notification to agency
        send_invoice_notification(@invoice)

        redirect_to invoice_path(@invoice), 
                    notice: 'Invoice created successfully and sent to agency.'
      else
        redirect_to vmcott_quotation_path(@quotation), 
                    alert: "Failed to create invoice: #{@invoice.errors.full_messages.join(', ')}"
      end
    end

    def vmcott_invoices
      @invoices = Invoice.where(vendor: 'VMCOTT')
                         .order(created_at: :desc)
                         .page(params[:page])
    end

    private

    def set_quotation
      @quotation = Quotation.find(params[:quotation_id])
      authorize! :manage, @quotation
    end

    def require_vmcott_user
      unless current_user.agency&.code == 'VMCOTT'
        redirect_to root_path, 
                    alert: 'Access restricted to VMCOTT users only.'
      end
    end

    def generate_invoice_number
      "INV-VMC-#{Date.today.strftime('%Y%m')}-#{SecureRandom.hex(4).upcase}"
    end

    def send_invoice_notification(invoice)
      # Send email notification
      InvoiceMailer.invoice_created(invoice).deliver_later if defined?(InvoiceMailer)
      
      # Create in-app notification for agency
      Notification.create!(
        user_id: invoice.vehicle.agency.users.finance.first&.id,
        title: "New Invoice from VMCOTT",
        message: "Invoice #{invoice.invoice_number} has been created for quotation #{invoice.quotation.quote_number}",
        link: invoice_path(invoice),
        priority: 'high'
      )
    end
  end
end