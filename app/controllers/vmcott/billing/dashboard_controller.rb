class Vmcott::Billing::DashboardController < ApplicationController
  before_action :authenticate_user!
  before_action :require_billing_officer

  def index
    # Parts that need RFQs (sent from Parts Coordinator)
    @pending_parts_requests = PartsRequest.where(status: 'billing_notified')
                                          .includes(:inspection, :part)
                                          .order(created_at: :asc)
    
    # Active RFQs waiting for vendor responses
    @active_rfqs = VendorRfq.where(status: 'sent')
                            .includes(:vendor_quotations)
                            .order(due_date: :asc)
    
    # FIXED: Safely get VendorRfq objects that have quotations received
    # First get PartsRequest with quotations_received status
    parts_with_quotes = PartsRequest.where(status: 'quotations_received')
                                    .includes(:inspection, :part)
                                    .order(updated_at: :desc)
    
    # Safely get RFQ IDs from parts
    rfq_ids = []
    parts_with_quotes.each do |pr|
      begin
        # Check if the part has rfqs association
        if pr.part.present? && pr.part.respond_to?(:vendor_rfq_items)
          # Get RFQ IDs through vendor_rfq_items
          item_rfq_ids = pr.part.vendor_rfq_items.pluck(:vendor_rfq_id).compact
          rfq_ids.concat(item_rfq_ids)
        end
        
        # Alternative: if there's a direct rfqs association on PartsRequest
        if pr.respond_to?(:rfqs) && pr.rfqs.present?
          rfq_ids.concat(pr.rfqs.pluck(:id))
        end
      rescue => e
        Rails.logger.error "Error getting RFQs for PartsRequest #{pr.id}: #{e.message}"
      end
    end
    
    # Get unique RFQ IDs
    rfq_ids = rfq_ids.uniq
    
    @quotations_received = if rfq_ids.any?
      VendorRfq.where(id: rfq_ids)
               .includes(:vendor_quotations, :vendor_rfq_items)
               .order(updated_at: :desc)
    else
      []
    end
    
    # Parts that have been received and need stock update
    @parts_received = PartsRequest.where(status: 'parts_received')
                                  .where(in_stock: false)
                                  .includes(:inspection, :part, :purchase_order)
                                  .order(parts_received_at: :desc)
    
    # For the KPI cards
    @pending_invoices = Invoice.where(status: 'pending').count
    @quotations_received_count = @quotations_received.count
    @pending_finance_review_count = PartsRequest.where(status: 'finance_review').count
    @pending_pos_count = PurchaseOrder.where(status: 'pending_approval').count
    @pending_rfqs_count = VendorRfq.where(status: 'draft').count
  end

  private

  def require_billing_officer
    unless current_user.finance? || current_user.admin? || current_user.vmcott_staff?
      redirect_to root_path, alert: "Access denied. Billing Officer access only."
    end
  end
end