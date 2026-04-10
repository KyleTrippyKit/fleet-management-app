class Vmcott::WorkshopSupervisor::PartsRequestsController < ApplicationController
  before_action :authenticate_user!
  before_action :require_workshop_supervisor
  before_action :set_parts_request, only: [:review, :approve, :reject]
  
  def review
    @job = @parts_request.inspection_job
    @original_part = @job.inspection_job_parts.find_by(part_id: @parts_request.part_id)
  end
  
  def approve
    @parts_request = PartsRequest.find(params[:id])
    
    # ✅ Safe part reservation with lock
    Part.transaction do
      # ✅ CORRECT locking syntax
      part = Part.find(@parts_request.part_id).lock!
      
      if part.current_stock >= @parts_request.quantity
        part.update!(
          quantity_reserved: part.quantity_reserved.to_i + @parts_request.quantity
        )
        @parts_request.update!(
          status: 'approved', 
          in_stock: true, 
          approved_at: Time.current,
          approved_by_id: current_user.id
        )
        flash[:notice] = "Parts approved and reserved"
      else
        @parts_request.update!(
          status: 'approved', 
          in_stock: false, 
          approved_at: Time.current,
          approved_by_id: current_user.id
        )
        flash[:warning] = "Parts approved but need ordering (insufficient stock)"
      end
    end
    
    redirect_to vmcott_workshop_supervisor_job_path(@parts_request.inspection_job)
  end
  
  def reject
    @parts_request.update!(
      status: 'rejected',
      rejection_reason: params[:reason],
      approved_by_id: current_user.id,
      approved_at: Time.current
    )
    
    flash[:alert] = "Parts request rejected"
    redirect_to vmcott_workshop_supervisor_job_path(@parts_request.inspection_job)
  end
  
  private
  
  def set_parts_request
    @parts_request = PartsRequest.find(params[:id])
  end
  
  def require_workshop_supervisor
    unless current_user.role == 'workshop_supervisor' || current_user.admin?
      redirect_to root_path, alert: "Access denied"
    end
  end
end