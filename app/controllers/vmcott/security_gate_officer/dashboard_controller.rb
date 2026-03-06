# app/controllers/vmcott/security_gate_officer/dashboard_controller.rb
# Security Gate Officer Controller - Handles vehicle check-in and condition reporting
# Renamed from receptionist to security_gate_officer

class Vmcott::SecurityGateOfficer::DashboardController < ApplicationController
  before_action :authenticate_user!
  before_action :require_security_gate_officer
  
  def index
    # Vehicles expected today (from scheduled appointments)
    @expected_arrivals = if defined?(PurchaseOrder) && defined?(ReceptionLog)
      # Get POs that are expected but not yet checked in
      purchase_orders = PurchaseOrder.where(vendor: 'VMCOTT', status: 'ordered')
                                    .where.not(id: ReceptionLog.where.not(purchase_order_id: nil).pluck(:purchase_order_id))
      
      # Format for display
      @expected_arrivals_count = purchase_orders.count
      purchase_orders.limit(10).map do |po|
        OpenStruct.new(
          vehicle: po.vehicle,
          agency: po.vehicle&.agency,
          purpose: "Service Work - PO ##{po.po_number}",
          scheduled_time: po.created_at,
          checked_in: ReceptionLog.exists?(purchase_order_id: po.id)
        )
      end
    else
      @expected_arrivals_count = 0
      []
    end
    
    # Recent check-ins (last 24 hours)
    @recent_checkins = if defined?(ReceptionLog)
      ReceptionLog.includes(:vehicle, :security_gate_officer, :condition_report)
                  .where(received_at: 24.hours.ago..Time.current)
                  .order(received_at: :desc)
                  .limit(10)
    else
      []
    end
    
    # Vehicles currently on site (checked in but not checked out)
    @vehicles_on_site = if defined?(ReceptionLog) && defined?(VehicleStatus)
      ReceptionLog.where(check_out_time: nil)
                  .where('received_at > ?', 24.hours.ago)
                  .count
    else
      0
    end
    
    # Vehicles ready for pickup (from finance)
    @ready_for_pickup = if defined?(Inspection)
      Inspection.where(status: 'ready_for_pickup')
                .includes(:vehicle)
                .count
    else
      0
    end
    
    # Today's counts
    @today_checkins = if defined?(ReceptionLog)
      ReceptionLog.where(received_at: Date.current.all_day).count
    else
      0
    end
    
    @pending_condition_reports = if defined?(VehicleConditionReport)
      VehicleConditionReport.where(status: 'draft').count
    else
      0
    end
    
    # Stats for KPI cards
    @stats = {
      today_checkins: @today_checkins,
      vehicles_on_site: @vehicles_on_site,
      ready_for_pickup: @ready_for_pickup,
      expected_arrivals: @expected_arrivals_count,
      pending_reports: @pending_condition_reports
    }
  end
  
  def scan
    # Renders QR code scanner view
    # Will handle both QR code scanning and manual entry fallback
  end
  
  def manual_entry
    # Get all RFQs with vehicles
    @rfqs_with_vehicles = if defined?(VendorRfq)
      VendorRfq.where(status: ['sent', 'draft'])
                .includes(vendor_rfq_items: :part)
                .order(created_at: :desc)
                .map do |rfq|
                  vehicle = find_vehicle_for_rfq(rfq)
                  
                  # Add vehicle to rfq instance for view
                  rfq.instance_variable_set(:@vehicle, vehicle)
                  
                  def rfq.vehicle
                    @vehicle
                  end
                  
                  def rfq.vehicle_id
                    @vehicle&.id
                  end
                  
                  def rfq.display_name
                    if @vehicle
                      "#{rfq_number} - #{@vehicle.license_plate} (#{@vehicle.make} #{@vehicle.model})"
                    else
                      "#{rfq_number} - No vehicle"
                    end
                  end
                  
                  rfq
                end
    else
      []
    end
    
    # Get POs with vehicles (backward compatibility)
    @purchase_orders_with_vehicles = if defined?(PurchaseOrder)
      PurchaseOrder.where(vendor: 'VMCOTT', status: 'ordered')
                  .where.not(vehicle_id: nil)
                  .order(created_at: :desc)
    else
      []
    end
    
    # Allow creation of new vehicle if needed
    @allow_new_vehicle = true
  end
  
  def receive_vehicle
    # Find or create vehicle
    if params[:vehicle_id].present?
      @vehicle = Vehicle.find_by(id: params[:vehicle_id])
    elsif params[:rfq_id].present?
      @rfq = VendorRfq.find_by(id: params[:rfq_id])
      @vehicle = find_vehicle_for_rfq(@rfq) if @rfq
    elsif params[:purchase_order_id].present?
      @po = PurchaseOrder.find_by(id: params[:purchase_order_id])
      @vehicle = @po&.vehicle
    elsif params[:new_vehicle].present?
      # Create new vehicle (for public clients)
      @vehicle = Vehicle.new(vehicle_params)
      if @vehicle.save
        # Success
      else
        flash[:alert] = "Could not create vehicle: #{@vehicle.errors.full_messages.join(', ')}"
        redirect_to vmcott_security_gate_officer_manual_entry_path and return
      end
    end
    
    if @vehicle.nil?
      flash[:alert] = "No vehicle selected. Please search for a vehicle or select an RFQ."
      redirect_to vmcott_security_gate_officer_manual_entry_path and return
    end
    
    # Store vehicle in session for condition check
    session[:check_in_vehicle_id] = @vehicle.id
    session[:check_in_rfq_id] = @rfq&.id
    session[:check_in_po_id] = @po&.id
    session[:driver_name] = params[:driver_name]
    
    # Redirect to condition check form
    redirect_to vmcott_security_gate_officer_condition_check_path(@vehicle.id)
  end
  
  def condition_check
    @vehicle = Vehicle.find(params[:vehicle_id])
    
    # Check if we have a pending check-in
    unless session[:check_in_vehicle_id].to_i == @vehicle.id
      flash[:alert] = "Please start the check-in process first."
      redirect_to vmcott_security_gate_officer_manual_entry_path and return
    end
    
    # Initialize a new condition report
    @condition_report = VehicleConditionReport.new(
      vehicle: @vehicle,
      security_gate_officer: current_user
    )
    
    # Pre-fill from session if available
    @driver_name = session[:driver_name]
  end
  
  def submit_condition
    @vehicle = Vehicle.find(params[:vehicle_id])
    
    # Verify session
    unless session[:check_in_vehicle_id].to_i == @vehicle.id
      flash[:alert] = "Session expired. Please start over."
      redirect_to vmcott_security_gate_officer_manual_entry_path and return
    end
    
    # Create condition report
    @condition_report = VehicleConditionReport.new(
      vehicle: @vehicle,
      security_gate_officer: current_user,
      fuel_level: params[:fuel_level],
      odometer: params[:odometer],
      driver_name: params[:driver_name],
      driver_id_number: params[:driver_id_number],
      signature_data: params[:signature_data],
      signed_at: Time.current,
      status: 'completed',
      ip_address: request.remote_ip,
      user_agent: request.user_agent
    )
    
    # Handle condition data
    condition_data = {}
    
    # Exterior damage (array)
    condition_data[:exterior_damage] = params[:exterior] || []
    condition_data[:exterior_notes] = params[:exterior_notes]
    
    # Interior issues (array)
    condition_data[:interior_issues] = params[:interior] || []
    
    # Tire status (radio)
    condition_data[:tire_status] = params[:tire_status] || 'good'
    condition_data[:tire_notes] = params[:tire_notes]
    
    # Warning lights (array)
    condition_data[:warning_lights] = params[:warnings] || ['none']
    
    # Additional notes
    condition_data[:additional_notes] = params[:notes]
    
    # Photos taken checklist
    photos_taken = []
    photos_taken << 'front' if params[:photo_front].present?
    photos_taken << 'rear' if params[:photo_rear].present?
    photos_taken << 'left' if params[:photo_left].present?
    photos_taken << 'right' if params[:photo_right].present?
    photos_taken << 'dashboard' if params[:photo_dashboard].present?
    photos_taken << 'odometer' if params[:photo_odometer].present?
    photos_taken << 'fuel_gauge' if params[:photo_fuel].present?
    photos_taken << 'damage' if params[:photo_damage].present?
    condition_data[:photos_taken] = photos_taken
    
    @condition_report.condition_data = condition_data
    
    # Handle acknowledgment
    acknowledgment = {
      driver_name: params[:driver_name],
      driver_id_number: params[:driver_id_number],
      signature_data: params[:signature_data],
      signed_at: Time.current,
      ip_address: request.remote_ip,
      user_agent: request.user_agent
    }
    @condition_report.acknowledgment = acknowledgment
    
    # Save the report
    if @condition_report.save
      # Attach photos if any
      attach_photos(@condition_report, params)
      
      # Create reception log
      reception_log = ReceptionLog.create!(
        vehicle: @vehicle,
        security_gate_officer: current_user,
        driver_name: params[:driver_name],
        received_at: Time.current,
        check_in_time: Time.current,
        visitor_name: params[:driver_name],
        notes: params[:notes],
        status: 'checked_in',
        condition_report: @condition_report,
        condition_status: @condition_report.exterior_damage? ? 'damage_noted' : 'clean'
      )
      
      # Add RFQ or PO reference if present
      if session[:check_in_rfq_id].present?
        reception_log.update(rfq_id: session[:check_in_rfq_id])
      elsif session[:check_in_po_id].present?
        reception_log.update(purchase_order_id: session[:check_in_po_id])
      end
      
      # Create vehicle status
      VehicleStatus.create!(
        vehicle: @vehicle,
        created_by: current_user,
        status: 'vehicle_received',
        current: true,
        notes: "Vehicle received from #{params[:driver_name]}. Condition: #{@condition_report.exterior_damage? ? 'Damage noted' : 'Clean'}"
      )
      
      # Clear session
      session.delete(:check_in_vehicle_id)
      session.delete(:check_in_rfq_id)
      session.delete(:check_in_po_id)
      session.delete(:driver_name)
      
      # Notify inspectors
      notify_inspectors(@vehicle, @condition_report)
      
      flash[:notice] = "Vehicle #{@vehicle.license_plate} checked in successfully. Driver acknowledgment captured."
      redirect_to vmcott_security_gate_officer_dashboard_path
    else
      flash[:alert] = "Error saving condition report: #{@condition_report.errors.full_messages.join(', ')}"
      render :condition_check
    end
  rescue => e
    Rails.logger.error "Error in submit_condition: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    flash[:alert] = "An error occurred: #{e.message}"
    redirect_to vmcott_security_gate_officer_condition_check_path(@vehicle.id)
  end
  
  def reception_logs
    @logs = ReceptionLog.includes(:vehicle, :security_gate_officer, :condition_report)
                        .order(received_at: :desc)
                        .page(params[:page])
                        .per(20)
  end
  
  def show_reception_log
    @log = ReceptionLog.includes(:vehicle, :security_gate_officer, :condition_report, :inspector)
                       .find(params[:id])
  end
  
  def today_logs
    @logs = ReceptionLog.includes(:vehicle, :security_gate_officer)
                        .where(received_at: Date.current.all_day)
                        .order(received_at: :desc)
  end
  
  def condition_report
    @report = VehicleConditionReport.includes(:vehicle, :security_gate_officer)
                                    .find(params[:id])
    
    respond_to do |format|
      format.html
      format.pdf do
        # Generate PDF for printing/signing
        pdf = generate_condition_report_pdf(@report)
        send_data pdf.render, filename: "condition_report_#{@report.id}.pdf", type: 'application/pdf'
      end
    end
  end
  
  private
  
  def require_security_gate_officer
    unless current_user.security_gate_officer? || current_user.admin?
      redirect_to root_path, alert: "Access denied. Security Gate Officer privileges required."
    end
  end
  
  def vehicle_params
    params.require(:vehicle).permit(
      :license_plate, :make, :model, :year_of_manufacture,
      :vehicle_type, :color, :agency_id
    )
  end
  
  def find_vehicle_for_rfq(rfq)
    return nil unless rfq
    
    # Get all part IDs from this RFQ
    part_ids = rfq.vendor_rfq_items.pluck(:part_id).compact
    
    return nil if part_ids.empty?
    
    # Try to find vehicle through parts associations
    Vehicle.joins(maintenances: :maintenance_parts)
           .where(maintenance_parts: { part_id: part_ids })
           .first ||
    Vehicle.joins(inspections: :parts_requests)
           .where(parts_requests: { part_id: part_ids })
           .first
  end
  
  def attach_photos(report, params)
    # Front view
    if params[:photo_front].present?
      report.condition_photos.attach(
        io: params[:photo_front],
        filename: "front_#{Time.current.to_i}.jpg",
        content_type: params[:photo_front].content_type
      )
    end
    
    # Rear view
    if params[:photo_rear].present?
      report.condition_photos.attach(
        io: params[:photo_rear],
        filename: "rear_#{Time.current.to_i}.jpg",
        content_type: params[:photo_rear].content_type
      )
    end
    
    # Left side
    if params[:photo_left].present?
      report.condition_photos.attach(
        io: params[:photo_left],
        filename: "left_#{Time.current.to_i}.jpg",
        content_type: params[:photo_left].content_type
      )
    end
    
    # Right side
    if params[:photo_right].present?
      report.condition_photos.attach(
        io: params[:photo_right],
        filename: "right_#{Time.current.to_i}.jpg",
        content_type: params[:photo_right].content_type
      )
    end
    
    # Dashboard
    if params[:photo_dashboard].present?
      report.condition_photos.attach(
        io: params[:photo_dashboard],
        filename: "dashboard_#{Time.current.to_i}.jpg",
        content_type: params[:photo_dashboard].content_type
      )
    end
    
    # Odometer
    if params[:photo_odometer].present?
      report.condition_photos.attach(
        io: params[:photo_odometer],
        filename: "odometer_#{Time.current.to_i}.jpg",
        content_type: params[:photo_odometer].content_type
      )
    end
    
    # Fuel gauge
    if params[:photo_fuel].present?
      report.condition_photos.attach(
        io: params[:photo_fuel],
        filename: "fuel_#{Time.current.to_i}.jpg",
        content_type: params[:photo_fuel].content_type
      )
    end
    
    # Damage photos
    if params[:photo_damage].present?
      report.condition_photos.attach(
        io: params[:photo_damage],
        filename: "damage_#{Time.current.to_i}.jpg",
        content_type: params[:photo_damage].content_type
      )
    end
  end
  
  def notify_inspectors(vehicle, condition_report)
    return unless defined?(Notification)
    
    inspector_ids = User.where(role: 'inspector').pluck(:id)
    
    damage_notice = condition_report.exterior_damage? ? "Damage noted: #{condition_report.exterior_damage_summary}" : "No damage reported"
    
    Notification.create!(
      title: "Vehicle Ready for Inspection",
      message: "#{vehicle.license_plate} received. #{damage_notice}",
      link: vmcott_inspector_pre_inspection_path(vehicle.id),
      user_id: inspector_ids,
      notifiable_type: 'Vehicle',
      notifiable_id: vehicle.id
    )
  rescue => e
    Rails.logger.error "Failed to create notification: #{e.message}"
  end
  
  def generate_condition_report_pdf(report)
    # This would use Prawn or similar to generate a PDF
    # For now, just return nil
    nil
  end
end