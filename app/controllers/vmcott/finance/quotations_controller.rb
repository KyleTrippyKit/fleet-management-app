# app/controllers/vmcott/finance/quotations_controller.rb
class Vmcott::Finance::QuotationsController < QuotationsController
  before_action :authenticate_user!
  before_action :require_finance
  before_action :set_inspection, only: [:new_for_inspection, :create_for_inspection]

  # Override index to add finance-specific filtering
  def index
    # Call the parent controller's index first
    super
    
    # Add finance-specific filters or scopes
    # For example, only show VMCOTT quotations for finance team
    @quotations = @quotations.where(vendor: 'VMCOTT')
  end

  # Override show to add finance-specific context
  def show
    # Call the parent controller's show
    super
    
    # Add finance-specific instance variables if needed
    @finance_notes = @quotation.metadata&.dig('finance_notes')
  end

  # Finance-specific actions
  def new_for_inspection
    @vehicle = @inspection.vehicle
    @jobs = @inspection.inspection_jobs
    @parts_requests = @inspection.parts_requests.where(in_stock: true)
    
    # Calculate totals
    @labor_cost = @jobs.sum(:estimated_labor_cost)
    @parts_cost = @parts_requests.sum { |pr| pr.part&.cost_price.to_f * pr.quantity }
    @total_cost = @labor_cost + @parts_cost
    
    # Determine if this is original or additional
    @is_additional = @inspection.metadata&.dig('additional_work') || false
    
    render 'vmcott/finance/quotations/new_for_inspection'
  end

  def create_for_inspection
    @quotation = Quotation.new(
      quote_number: generate_quote_number,
      vehicle: @inspection.vehicle,
      agency: @inspection.vehicle.agency,
      created_by: current_user,
      status: :draft,
      labor_cost: params[:labor_cost],
      parts_cost: params[:parts_cost],
      total_cost: params[:total_cost],
      valid_until: params[:valid_until] || 30.days.from_now,
      notes: params[:notes],
      metadata: {
        inspection_id: @inspection.id,
        is_additional: params[:is_additional] == 'true'
      }
    )

    if @quotation.save
      # Link to inspection
      @inspection.update!(quotation_id: @quotation.id)
      
      # Update status based on original vs additional
      if params[:is_additional] == 'true'
        @inspection.update!(status: :awaiting_customer_approval_additional)
      else
        @inspection.update!(status: :awaiting_customer_approval_original)
      end
      
      redirect_to vmcott_finance_quotation_path(@quotation), 
                  notice: "Quotation created and ready to send to agency."
    else
      render :new_for_inspection, alert: "Error creating quotation."
    end
  end

  def send_to_agency
    @quotation = Quotation.find(params[:id])
    
    @quotation.update!(
      status: :sent,
      sent_at: Time.current,
      vendor: 'VMCOTT' # Ensure vendor is set correctly
    )
    
    # Notify PTSC
    notify_agency(@quotation)
    
    redirect_to vmcott_finance_quotation_path(@quotation), 
                notice: "Quotation sent to agency."
  end

  private

  def set_inspection
    @inspection = Inspection.find(params[:inspection_id])
  end

  def require_finance
    unless current_user.finance? || current_user.admin?
      redirect_to root_path, alert: "Access denied. Finance privileges required."
    end
  end

  def generate_quote_number
    "Q-#{Date.current.strftime('%Y%m%d')}-#{SecureRandom.hex(4).upcase}"
  end

  def notify_agency(quotation)
    agency_users = User.where(agency: quotation.agency, role: ['admin', 'finance'])
    Notification.create!(
      title: "New Quotation from VMCOTT",
      message: "Quotation #{quotation.quote_number} for #{quotation.vehicle.license_plate} is ready for review.",
      link: "/ptsc/admin/quotations/#{quotation.id}",
      user_id: agency_users.pluck(:id),
      notifiable_type: 'Quotation',
      notifiable_id: quotation.id
    )
  rescue => e
    Rails.logger.error "Failed to create notification: #{e.message}"
    # Don't crash if notification fails
  end
end