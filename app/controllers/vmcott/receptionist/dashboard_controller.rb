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
    # Get POs that have vehicles assigned for the dropdown
    @purchase_orders_with_vehicles = if defined?(PurchaseOrder)
      PurchaseOrder.where(vendor: 'VMCOTT', status: 'ordered')
                  .where.not(vehicle_id: nil)
                  .order(created_at: :desc)
    else
      []
    end
  end
  
  def receive_vehicle
    # Case 1: Vehicle selected via search
    if params[:vehicle_id].present?
      @vehicle = Vehicle.find_by(id: params[:vehicle_id])
      
    # Case 2: Purchase Order selected (must have vehicle)
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
      @log = ReceptionLog.create!(
        vehicle: @vehicle,
        user_id: current_user.id,  # Using user_id instead of receptionist
        agency_id: current_user.agency_id,
        driver_name: params[:driver_name],
        received_at: Time.current,
        check_in_time: Time.current,
        visitor_name: params[:driver_name] || 'Unknown',
        notes: params[:notes],
        purchase_order_id: params[:purchase_order_id],
        status: 'checked_in'  # Changed from 'pending_inspection' to valid status
      )
      
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
      
      # Create notification for inspectors (FIXED: changed 'link' to 'action_url')
      if defined?(Notification)
        begin
          Notification.create!(
            title: "Vehicle Received",
            message: "#{@vehicle.license_plate} received and ready for inspection",
            action_url: vmcott_inspector_new_inspection_path(vehicle_id: @vehicle.id),
            user_id: nil,  # Will be assigned to all inspectors via a job
            notifiable_type: 'Vehicle',
            notifiable_id: @vehicle.id,
            read: false
          )
          
          # You might want to create notifications for all inspectors here
          # Or use a background job to notify all inspectors
          notify_inspectors(@vehicle)
        rescue => e
          Rails.logger.error "Failed to create notification: #{e.message}"
        end
      end
      
      redirect_to vmcott_receptionist_dashboard_path, notice: "Vehicle #{@vehicle.license_plate} received successfully"
    else
      flash[:alert] = "No vehicle selected. Please search for a vehicle or select a Purchase Order with an associated vehicle."
      redirect_to vmcott_receptionist_manual_entry_path
    end
  end
  
  private
  
  def require_receptionist
    unless current_user.receptionist? || current_user.admin?
      redirect_to root_path, alert: "Access denied. Receptionist privileges required."
    end
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