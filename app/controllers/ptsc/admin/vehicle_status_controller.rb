class Ptsc::Admin::VehicleStatusController < ApplicationController
  before_action :authenticate_user!
  before_action :require_ptsc_admin

  def index
    # Get all PTSC vehicles that are at VMCOTT
    @vehicles_at_vmcott = Vehicle.joins(:agency)
                                  .where(agencies: { code: 'PTSC' })
                                  .where(status: ['at_vmcott', 'in_progress', 'pending_inspection', 'approved_for_repair', 'ready_for_qc', 'ready_for_pickup'])
                                  .includes(:reception_logs, :inspections, :vehicle_statuses)
                                  .order(updated_at: :desc)

    # Count statistics
    @at_vmcott_count = @vehicles_at_vmcott.count
    @in_progress_count = @vehicles_at_vmcott.select { |v| v.status.in?(['in_progress', 'approved_for_repair', 'ready_for_qc']) }.count
    @ready_for_pickup_count = @vehicles_at_vmcott.select { |v| v.status == 'ready_for_pickup' }.count
    @completed_count = Vehicle.joins(:agency)
                              .where(agencies: { code: 'PTSC' })
                              .where(status: 'completed')
                              .count
    
    # ✅ FIX: Use vehicle.agency_id through association instead of direct agency_id
    @awaiting_quote_count = Quotation.where(agency_id: current_user.agency_id, status: 'sent').count
    
    # ✅ FIX: PurchaseOrders don't have agency_id, so get through vehicles
    @awaiting_po_count = PurchaseOrder.joins(:vehicle)
                                      .where(vehicles: { agency_id: current_user.agency_id })
                                      .where(status: 'pending_approval')
                                      .count
    
    # ✅ FIX: Get pending quotations
    @pending_quotations = Quotation.where(agency_id: current_user.agency_id, status: 'sent')
                                   .includes(:vehicle)
                                   .order(created_at: :desc)
                                   .limit(10)
  end

  def show
    @vehicle = Vehicle.find(params[:id])
    @status_history = @vehicle.vehicle_statuses.order(created_at: :desc)
    @current_status = @vehicle.current_status
    @timeline = build_timeline(@vehicle)
  end

  def history
    @vehicle = Vehicle.find(params[:id])
    @status_history = @vehicle.vehicle_statuses.order(created_at: :desc)
  end

  private

  def require_ptsc_admin
    unless current_user.admin? && current_user.agency&.code == 'PTSC'
      redirect_to root_path, alert: "Access denied. PTSC Admin only."
    end
  end

  def build_timeline(vehicle)
    timeline = []
    
    # Reception
    if (reception = vehicle.reception_logs.last)
      timeline << {
        stage: 'Received',
        time: reception.check_in_time,
        status: 'completed',
        icon: 'door-open'
      }
    end
    
    # Inspection
    if (inspection = vehicle.inspections.last)
      timeline << {
        stage: 'Inspection',
        time: inspection.completed_at || inspection.created_at,
        status: inspection.completed_at? ? 'completed' : 'current',
        icon: 'search'
      }
    end
    
    # Parts
    if vehicle.parts_requests.any?
      all_parts_received = vehicle.parts_requests.where(in_stock: false).empty?
      timeline << {
        stage: 'Parts',
        time: vehicle.parts_requests.last.updated_at,
        status: all_parts_received ? 'completed' : 'current',
        icon: 'box-seam'
      }
    end
    
    # Workshop
    if vehicle.inspection_jobs.any?
      all_jobs_done = vehicle.inspection_jobs.all? { |j| j.completed_at.present? }
      timeline << {
        stage: 'Workshop',
        time: vehicle.inspection_jobs.last.updated_at,
        status: all_jobs_done ? 'completed' : 'current',
        icon: 'tools'
      }
    end
    
    # QC
    if vehicle.inspections.last&.final_inspection_completed_at
      timeline << {
        stage: 'QC',
        time: vehicle.inspections.last.final_inspection_completed_at,
        status: 'completed',
        icon: 'clipboard-check'
      }
    elsif vehicle.status == 'ready_for_qc'
      timeline << {
        stage: 'QC',
        time: vehicle.updated_at,
        status: 'current',
        icon: 'clipboard-check'
      }
    end
    
    # Ready
    if vehicle.status == 'ready_for_pickup'
      timeline << {
        stage: 'Ready',
        time: vehicle.updated_at,
        status: 'current',
        icon: 'truck'
      }
    end
    
    timeline
  end
end