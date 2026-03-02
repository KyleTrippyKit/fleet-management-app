# app/controllers/ptsc/admin/quotations_controller.rb
class Ptsc::Admin::QuotationsController < ApplicationController
  before_action :authenticate_user!
  before_action :require_ptsc_admin
  before_action :set_quotation, only: [:show, :approve, :reject]

  def index
    @pending_quotations = Quotation.where(
      agency: current_user.agency, 
      status: :sent
    ).order(created_at: :desc)
    
    @approved_quotations = Quotation.where(
      agency: current_user.agency, 
      status: :accepted
    ).order(created_at: :desc)
    
    @rejected_quotations = Quotation.where(
      agency: current_user.agency, 
      status: :rejected
    ).order(created_at: :desc)
  end

  def show
    @vehicle = @quotation.vehicle
    @is_additional = @quotation.metadata&.dig('is_additional') || false
  end

  def approve
    if @quotation.update(
        status: :accepted,
        accepted_at: Time.current
      )
      
      # Update inspection status
      inspection_id = @quotation.metadata&.dig('inspection_id')
      if inspection_id
        inspection = Inspection.find(inspection_id)
        
        if @quotation.metadata&.dig('is_additional')
          inspection.update!(status: :approved_for_repair)
        else
          inspection.update!(status: :approved_for_repair)
        end
      end
      
      # Create purchase order from quotation
      po = create_purchase_order_from_quotation(@quotation)
      
      # Notify VMCOTT finance
      notify_vmcott_finance(po)
      
      redirect_to ptsc_admin_quotation_path(@quotation), 
                  notice: "Quotation approved. Purchase Order created."
    else
      redirect_to ptsc_admin_quotation_path(@quotation), 
                  alert: "Error approving quotation."
    end
  end

  def reject
    if @quotation.update(
        status: :rejected,
        rejected_at: Time.current,
        metadata: @quotation.metadata.merge(rejection_reason: params[:reason])
      )
      
      # Update inspection status
      inspection_id = @quotation.metadata&.dig('inspection_id')
      if inspection_id
        inspection = Inspection.find(inspection_id)
        inspection.update!(status: :cancelled_by_agency)
      end
      
      redirect_to ptsc_admin_quotations_path, 
                  notice: "Quotation rejected."
    else
      redirect_to ptsc_admin_quotation_path(@quotation), 
                  alert: "Error rejecting quotation."
    end
  end

  private

  def set_quotation
    @quotation = Quotation.find(params[:id])
  end

  def require_ptsc_admin
    unless current_user.agency&.code == 'PTSC' && 
           (current_user.admin? || current_user.finance?)
      redirect_to root_path, alert: "Access denied."
    end
  end

  def create_purchase_order_from_quotation(quotation)
    PurchaseOrder.create!(
      po_number: "PO-PTSC-#{Date.current.strftime('%Y%m%d')}-#{SecureRandom.hex(4).upcase}",
      vendor: 'VMCOTT',
      amount: quotation.total_cost,
      status: 'pending_approval',
      quotation: quotation,
      vehicle: quotation.vehicle,
      created_by: current_user
    )
  end

  def notify_vmcott_finance(po)
    finance_users = User.where(agency: Agency.find_by(code: 'VMCOTT'), role: ['finance', 'admin'])
    Notification.create!(
      title: "Purchase Order Received",
      message: "PO #{po.po_number} received from PTSC for approved quotation.",
      link: "/vmcott/finance/purchase_orders/#{po.id}",
      user_id: finance_users.pluck(:id),
      notifiable_type: 'PurchaseOrder',
      notifiable_id: po.id
    )
  end
end