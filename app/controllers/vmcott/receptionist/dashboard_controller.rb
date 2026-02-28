class Vmcott::Receptionist::DashboardController < ApplicationController
  before_action :authenticate_user!
  before_action :require_receptionist
  
  def index
    @pending_receptions = PurchaseOrder.where(vendor: 'VMCOTT', status: 'ordered')
                                      .where.not(id: ReceptionLog.where.not(purchase_order_id: nil).pluck(:purchase_order_id))
                                      .count if defined?(PurchaseOrder) && defined?(ReceptionLog)
    @recent_receptions = ReceptionLog.includes(:vehicle, :receptionist)
                                     .order(received_at: :desc)
                                     .limit(10) if defined?(ReceptionLog)
    @todays_count = ReceptionLog.today.count if defined?(ReceptionLog)
  end
  
  def scan
    # Renders app/views/vmcott/receptionist/dashboard/scan.html.erb
  end
  
  def manual_entry
    # Get POs that have vehicles assigned for the dropdown
    @purchase_orders_with_vehicles = PurchaseOrder.where(vendor: 'VMCOTT', status: 'ordered')
                                                  .where.not(vehicle_id: nil)
                                                  .order(created_at: :desc)
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
      @log = ReceptionLog.create!(
        vehicle: @vehicle,
        receptionist: current_user,
        driver_name: params[:driver_name],
        received_at: Time.current,
        check_in_time: Time.current,
        visitor_name: params[:driver_name],
        notes: params[:notes],
        purchase_order_id: params[:purchase_order_id],
        status: 'pending_inspection'
      )
      
      @log.create_vehicle_status if @log.respond_to?(:create_vehicle_status)
      
      if defined?(Notification)
        Notification.create!(
          title: "Vehicle Received",
          message: "#{@vehicle.license_plate} received and ready for inspection",
          link: vmcott_inspector_new_inspection_path(vehicle_id: @vehicle.id),
          recipient_type: 'inspector'
        )
      end
      
      redirect_to vmcott_receptionist_dashboard_path, notice: "Vehicle received successfully"
    else
      flash[:alert] = "No vehicle selected. Please search for a vehicle or select a Purchase Order with an associated vehicle."
      redirect_to vmcott_receptionist_manual_entry_path
    end
  end
  
  private
  
  def require_receptionist
    unless current_user.receptionist? || current_user.admin?
      redirect_to root_path, alert: "Access denied"
    end
  end
end