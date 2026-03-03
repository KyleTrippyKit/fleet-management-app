# app/controllers/vmcott/receptionist/dashboard_controller.rb
class Vmcott::Receptionist::DashboardController < ApplicationController
  before_action :authenticate_user!
  before_action :require_receptionist
  
  def index
    @pending_receptions = if defined?(PurchaseOrder) && defined?(ReceptionLog)
      PurchaseOrder.where(vendor: 'VMCOTT', status: 'ordered')
                  .where.not(id: ReceptionLog.where.not(purchase_order_id: nil).pluck(:purchase_order_id))
                  .count
    else
      0
    end
    
    @recent_receptions = if defined?(ReceptionLog)
      ReceptionLog.includes(:vehicle, :receptionist)
                  .order(created_at: :desc)
                  .limit(10)
    else
      []
    end
    
    @todays_count = if defined?(ReceptionLog) && ReceptionLog.respond_to?(:today)
      ReceptionLog.today.count
    else
      0
    end
  end
  
  def scan
    # Renders app/views/vmcott/receptionist/dashboard/scan.html.erb
  end
  
  def manual_entry
    # Get all RFQs
    @rfqs_with_vehicles = if defined?(VendorRfq)
      VendorRfq.where(status: ['sent', 'draft'])
                .includes(vendor_rfq_items: :part)
                .order(created_at: :desc)
                .map do |rfq|
                  # Find vehicle for this RFQ
                  vehicle = find_vehicle_for_rfq(rfq)
                  
                  # Debug output to console
                  Rails.logger.info "=" * 50
                  Rails.logger.info "RFQ ##{rfq.id} - #{rfq.rfq_number}"
                  Rails.logger.info "Vehicle found: #{vehicle&.license_plate || 'NONE'}"
                  Rails.logger.info "Part IDs: #{rfq.vendor_rfq_items.pluck(:part_id).compact}"
                  Rails.logger.info "=" * 50
                  
                  # Add methods to the RFQ instance for the view
                  rfq.instance_variable_set(:@vehicle, vehicle)
                  
                  def rfq.vehicle
                    @vehicle
                  end
                  
                  def rfq.vehicle_id
                    @vehicle&.id
                  end
                  
                  def rfq.rfq_number_with_vehicle_info
                    if @vehicle
                      "#{rfq_number} - #{@vehicle.license_plate} (#{@vehicle.make} #{@vehicle.model})"
                    elsif @vehicle.nil? && @show_all
                      "#{rfq_number} - No vehicle (will create new reception without vehicle)"
                    else
                      "#{rfq_number} - No vehicle"
                    end
                  end
                  
                  rfq
                end
    else
      []
    end
    
    # Also keep POs for backward compatibility
    @purchase_orders_with_vehicles = if defined?(PurchaseOrder)
      PurchaseOrder.where(vendor: 'VMCOTT', status: 'ordered')
                  .where.not(vehicle_id: nil)
                  .order(created_at: :desc)
    else
      []
    end
    
    # Add option to create new vehicle
    @allow_new_vehicle = true
  end
  
  def receive_vehicle
    # Case 1: Vehicle selected via search
    if params[:vehicle_id].present?
      @vehicle = Vehicle.find_by(id: params[:vehicle_id])
      
    # Case 2: RFQ selected (need to find vehicle through associations)
    elsif params[:rfq_id].present?
      @rfq = VendorRfq.find_by(id: params[:rfq_id])
      
      if @rfq.present?
        # Try to find vehicle through various paths
        @vehicle = find_vehicle_for_rfq(@rfq)
        
        # If no vehicle found, we can still proceed but warn the user
        if @vehicle.nil?
          # Option 1: Reject with error
          # flash[:alert] = "Selected RFQ does not have an associated vehicle"
          # redirect_to vmcott_receptionist_manual_entry_path and return
          
          # Option 2: Allow but warn (uncomment this line and comment the above to allow)
          flash[:warning] = "This RFQ doesn't have an associated vehicle. Please select a vehicle manually or create a new reception without a vehicle link."
          redirect_to vmcott_receptionist_manual_entry_path and return
        end
      else
        flash[:alert] = "RFQ not found"
        redirect_to vmcott_receptionist_manual_entry_path and return
      end
      
    # Case 3: Purchase Order selected
    elsif params[:purchase_order_id].present?
      @purchase_order = PurchaseOrder.find_by(id: params[:purchase_order_id])
      
      if @purchase_order&.vehicle.present?
        @vehicle = @purchase_order.vehicle
      else
        flash[:alert] = "Selected Purchase Order does not have an associated vehicle"
        redirect_to vmcott_receptionist_manual_entry_path and return
      end
    end
    
    if @vehicle.present?
      # Create reception log
      reception_params = {
        vehicle: @vehicle,
        user_id: current_user.id,
        agency_id: current_user.agency_id,
        driver_name: params[:driver_name],
        received_at: Time.current,
        check_in_time: Time.current,
        visitor_name: params[:driver_name] || 'Unknown',
        notes: params[:notes],
        status: 'checked_in'
      }
      
      # Add RFQ or PO reference if present
      reception_params[:rfq_id] = @rfq.id if @rfq.present?
      reception_params[:purchase_order_id] = @purchase_order.id if @purchase_order.present?
      
      @log = ReceptionLog.create!(reception_params)
      
      # Create vehicle status
      begin
        VehicleStatus.create!(
          vehicle: @vehicle,
          created_by: current_user,
          status: 'vehicle_received',
          current: true,
          notes: "Vehicle received from agency by #{current_user.name}"
        )
      rescue => e
        Rails.logger.error "Failed to create vehicle status: #{e.message}"
      end
      
      # Create notification for inspectors
      if defined?(Notification)
        begin
          Notification.create!(
            title: "Vehicle Received",
            message: "#{@vehicle.license_plate} received and ready for inspection",
            action_url: vmcott_inspector_new_inspection_path(vehicle_id: @vehicle.id),
            user_id: nil,
            notifiable_type: 'Vehicle',
            notifiable_id: @vehicle.id,
            read: false
          )
          
          # Notify all inspectors
          notify_inspectors(@vehicle)
        rescue => e
          Rails.logger.error "Failed to create notification: #{e.message}"
        end
      end
      
      redirect_to vmcott_receptionist_dashboard_path, notice: "Vehicle #{@vehicle.license_plate} received successfully"
    else
      flash[:alert] = "No vehicle selected. Please search for a vehicle or select an RFQ/Purchase Order with an associated vehicle."
      redirect_to vmcott_receptionist_manual_entry_path
    end
  end
  
  private
  
  def require_receptionist
    unless current_user.receptionist? || current_user.admin?
      redirect_to root_path, alert: "Access denied. Receptionist privileges required."
    end
  end
  
  def find_vehicle_for_rfq(rfq)
    # Get all part IDs from this RFQ
    part_ids = rfq.vendor_rfq_items.pluck(:part_id).compact
    
    Rails.logger.info "Finding vehicle for RFQ ##{rfq.id} with part IDs: #{part_ids}"
    
    return nil if part_ids.empty?
    
    # Path 1: Through parts to maintenance_parts to maintenances to vehicles
    vehicle = Vehicle.joins(maintenances: :maintenance_parts)
                    .where(maintenance_parts: { part_id: part_ids })
                    .first
    if vehicle
      Rails.logger.info "Found vehicle via maintenances: #{vehicle.license_plate}"
      return vehicle
    end
    
    # Path 2: Through parts to parts_requests to inspections to vehicles
    vehicle = Vehicle.joins(inspections: :parts_requests)
                    .where(parts_requests: { part_id: part_ids })
                    .first
    if vehicle
      Rails.logger.info "Found vehicle via inspections: #{vehicle.license_plate}"
      return vehicle
    end
    
    # Path 3: Through parts to purchase_requests to ??? (if purchase_requests have vehicle association)
    # This depends on your schema
    
    Rails.logger.info "No vehicle found for RFQ ##{rfq.id}"
    nil
  end
  
  def notify_inspectors(vehicle)
    # Find all users with inspector role in the current agency
    inspectors = User.where(role: 'inspector', agency_id: current_user.agency_id)
    
    inspectors.each do |inspector|
      Notification.create!(
        title: "New Vehicle for Inspection",
        message: "Vehicle #{vehicle.license_plate} is ready for inspection",
        action_url: vmcott_inspector_new_inspection_path(vehicle_id: vehicle.id),
        user_id: inspector.id,
        notifiable_type: 'Vehicle',
        notifiable_id: vehicle.id,
        read: false
      )
    end
  rescue => e
    Rails.logger.error "Failed to notify inspectors: #{e.message}"
  end
end