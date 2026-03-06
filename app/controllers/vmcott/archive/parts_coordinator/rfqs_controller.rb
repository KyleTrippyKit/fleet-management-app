# app/controllers/vmcott/parts_coordinator/rfqs_controller.rb
class Vmcott::PartsCoordinator::RfqsController < ApplicationController
  before_action :authenticate_user!
  before_action :require_parts_coordinator

  def index
    if params[:inspection_id].present?
      @inspection = Inspection.find(params[:inspection_id])
      
      # Find RFQs through the parts_requests associated with the inspection
      parts_request_ids = @inspection.parts_requests.pluck(:id)
      
      # Find RFQ items that are linked to these parts requests through the part
      # This assumes VendorRfqItem belongs to part, and part has many parts_requests
      @rfqs = VendorRfq.joins(vendor_rfq_items: :part)
                       .where(parts: { id: PartsRequest.where(inspection_id: params[:inspection_id]).select(:part_id) })
                       .distinct
                       .order(created_at: :desc)
    else
      @rfqs = VendorRfq.where(processing_agency: current_user.agency)
                       .includes(:vendor_quotations, :vendor_rfq_items)
                       .order(created_at: :desc)
                       .page(params[:page]).per(20)
    end
  end

  def show
    @rfq = VendorRfq.find(params[:id])
    @quotations = @rfq.vendor_quotations.includes(:supplier, :vendor_quotation_lines)
  end

  private

  def require_parts_coordinator
    unless current_user.parts_coordinator? || current_user.admin?
      redirect_to root_path, alert: "Access denied. Parts Coordinator privileges required."
    end
  end
end