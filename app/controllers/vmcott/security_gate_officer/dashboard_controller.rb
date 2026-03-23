# app/controllers/vmcott/security_gate_officer/dashboard_controller.rb

class Vmcott::SecurityGateOfficer::DashboardController < ApplicationController
  # Skip the dashboard caching for this controller - THIS IS THE FIX!
  skip_around_action :cache_dashboard_data, if: :dashboard_controller?
  
  before_action :authenticate_user!
  before_action :require_security_gate_officer
  before_action :disable_caching

  def index
    # Today's check-ins
    @today_checkins = if defined?(ReceptionLog)
      ReceptionLog.where(received_at: Date.current.all_day).count
    else
      0
    end
    
    # Vehicles on site (checked in but not checked out)
    @vehicles_on_site = if defined?(ReceptionLog)
      ReceptionLog.where(check_out_time: nil)
                  .where('received_at > ?', 24.hours.ago)
                  .count
    else
      0
    end
    
    # Pending condition reports
    @pending_condition_reports = if defined?(VehicleConditionReport)
      VehicleConditionReport.where(status: 'draft').count
    else
      0
    end
    
    # Recent check-ins (last 24 hours)
    @recent_checkins = if defined?(ReceptionLog)
      ReceptionLog.includes(:vehicle, :condition_report)
                  .where(received_at: 24.hours.ago..Time.current)
                  .order(received_at: :desc)
                  .limit(10)
    else
      []
    end
    
    # Stats hash for the view
    @stats = {
      today_checkins: @today_checkins,
      vehicles_on_site: @vehicles_on_site,
      pending_reports: @pending_condition_reports
    }
    
    response.headers["Cache-Control"] = "no-cache, no-store, must-revalidate, max-age=0"
    response.headers["Pragma"] = "no-cache"
    response.headers["Expires"] = "Mon, 01 Jan 1990 00:00:00 GMT"
    
    render layout: 'application'
  end
  
  def scan
    response.headers["Cache-Control"] = "no-cache, no-store, must-revalidate, max-age=0"
    response.headers["Pragma"] = "no-cache"
    response.headers["Expires"] = "Mon, 01 Jan 1990 00:00:00 GMT"
    render layout: 'application'
  end
  
  def manual_entry
    @agencies = Agency.where(code: ['PTSC', 'TTPS', 'TTDF', 'VMCOTT']).order(:name)
    @allow_new_vehicle = true
    @is_new_vehicle_mode = params[:create_new_vehicle] == 'true'
    
    response.headers["Cache-Control"] = "no-cache, no-store, must-revalidate, max-age=0"
    response.headers["Pragma"] = "no-cache"
    response.headers["Expires"] = "Mon, 01 Jan 1990 00:00:00 GMT"
    
    render layout: 'application'
  end
  
  def receive_vehicle
    Rails.logger.info "Params: #{params.except(:authenticity_token).inspect}" if Rails.env.development?
  
    begin
      ActiveRecord::Base.transaction do
        vehicle = nil
        owner = nil
        
        client_type = params[:selected_client_type]
        
        if client_type.blank?
          flash[:alert] = "Please select a client type"
          redirect_to vmcott_security_gate_officer_manual_entry_path and return
        end
        
        # CASE 1: Existing vehicle selected
        if params[:vehicle_id].present?
          vehicle = Vehicle.find(params[:vehicle_id])
          owner = vehicle.owner
          Rails.logger.info "Found existing vehicle: #{vehicle.license_plate}" if Rails.env.development?
          
        # CASE 2: New vehicle being created
        elsif params[:new_vehicle].present? && params[:create_new_vehicle] == 'true'
          Rails.logger.info "Creating new vehicle" if Rails.env.development?
          
          if client_type == 'agency'
            if params[:agency_id].blank?
              flash[:alert] = "Please select an agency"
              redirect_to vmcott_security_gate_officer_manual_entry_path(create_new_vehicle: true) and return
            end
            owner = Agency.find(params[:agency_id])
            Rails.logger.info "Owner is agency: #{owner.code}" if Rails.env.development?
            
          elsif client_type == 'walkin'
            if params[:walkin][:name].blank?
              flash[:alert] = "Customer name is required"
              redirect_to vmcott_security_gate_officer_manual_entry_path(create_new_vehicle: true) and return
            end
            
            owner = Client.create!(
              name: params[:walkin][:name].to_s.strip,
              phone: params[:walkin][:phone].to_s.strip.presence,
              email: params[:walkin][:email].to_s.strip.presence,
              address: params[:walkin][:address].to_s.strip.presence,
              client_type: 'individual',
              payment_terms: 'cash',
              is_active: true
            )
            Rails.logger.info "Created walk-in client: #{owner.name}" if Rails.env.development?
            
          elsif client_type == 'new_company'
            if params[:company][:name].blank?
              flash[:alert] = "Company name is required"
              redirect_to vmcott_security_gate_officer_manual_entry_path(create_new_vehicle: true) and return
            end
            if params[:company][:contact_person].blank?
              flash[:alert] = "Contact person is required"
              redirect_to vmcott_security_gate_officer_manual_entry_path(create_new_vehicle: true) and return
            end
            if params[:company][:email].blank?
              flash[:alert] = "Email address is required"
              redirect_to vmcott_security_gate_officer_manual_entry_path(create_new_vehicle: true) and return
            end
            if params[:company][:address].blank?
              flash[:alert] = "Business address is required"
              redirect_to vmcott_security_gate_officer_manual_entry_path(create_new_vehicle: true) and return
            end
            if params[:company][:payment_terms].blank?
              flash[:alert] = "Please select payment terms"
              redirect_to vmcott_security_gate_officer_manual_entry_path(create_new_vehicle: true) and return
            end
            
            owner = Client.create!(
              name: "#{params[:company][:name].to_s.strip} - #{params[:company][:contact_person].to_s.strip}",
              phone: params[:company][:phone].to_s.strip.presence,
              email: params[:company][:email].to_s.strip,
              address: params[:company][:address].to_s.strip,
              client_type: 'corporate',
              payment_terms: params[:company][:payment_terms],
              is_active: true
            )
            Rails.logger.info "Created new company client: #{owner.name}" if Rails.env.development?
          end
          
          vehicle = Vehicle.new(new_vehicle_params)
          vehicle.owner = owner
          vehicle.skip_optional_validation = true
          
          unless vehicle.save
            error_msg = "Could not create vehicle: #{vehicle.errors.full_messages.join(', ')}"
            Rails.logger.error error_msg
            flash[:alert] = error_msg
            redirect_to vmcott_security_gate_officer_manual_entry_path(create_new_vehicle: true) and return
          end
          
          Rails.logger.info "Created new vehicle: #{vehicle.license_plate}" if Rails.env.development?
        else
          flash[:alert] = "No vehicle selected. Please search for a vehicle or add a new one."
          redirect_to vmcott_security_gate_officer_manual_entry_path and return
        end
        
        if vehicle.nil?
          flash[:alert] = "No vehicle selected. Please search for a vehicle or add a new one."
          redirect_to vmcott_security_gate_officer_manual_entry_path and return
        end
        
        # Store vehicle in session for condition check
        session[:check_in_vehicle_id] = vehicle.id
        session[:driver_name] = params[:driver_name]
        session[:driver_id] = params[:driver_id] if params[:driver_id].present?
        session[:notes] = params[:notes] if params[:notes].present?
        session[:client_type] = client_type
        
        if client_type == 'agency'
          session[:agency_id] = params[:agency_id]
        elsif client_type == 'walkin'
          session[:client_params] = {
            name: params[:walkin][:name],
            phone: params[:walkin][:phone],
            email: params[:walkin][:email],
            address: params[:walkin][:address],
            payment_terms: 'cash'
          }
        elsif client_type == 'new_company'
          session[:client_params] = {
            name: params[:company][:name],
            contact_person: params[:company][:contact_person],
            phone: params[:company][:phone],
            email: params[:company][:email],
            address: params[:company][:address],
            payment_terms: params[:company][:payment_terms]
          }
        end
        
        if params[:new_vehicle].present?
          session[:new_vehicle_params] = new_vehicle_params.to_h
        end
        
        Rails.logger.info "Session stored with vehicle_id: #{vehicle.id}" if Rails.env.development?
        
        redirect_to vmcott_security_gate_officer_condition_check_path(vehicle.id)
      end
    rescue => e
      Rails.logger.error "Error in receive_vehicle: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      flash[:alert] = "Error processing vehicle: #{e.message}"
      redirect_to vmcott_security_gate_officer_manual_entry_path
    end
  end
  
  def condition_check
    if params[:vehicle_id].present?
      @vehicle = Vehicle.find(params[:vehicle_id])
    elsif session[:check_in_vehicle_id].present?
      @vehicle = Vehicle.find(session[:check_in_vehicle_id])
    elsif params[:create_new_vehicle] == 'true' && session[:new_vehicle_params].present?
      @vehicle = create_vehicle_from_session
    else
      flash[:alert] = "No vehicle selected. Please start the check-in process."
      redirect_to vmcott_security_gate_officer_manual_entry_path and return
    end
    
    if session[:check_in_vehicle_id].present? && session[:check_in_vehicle_id].to_i != @vehicle.id
      flash[:alert] = "Session mismatch. Please start over."
      redirect_to vmcott_security_gate_officer_manual_entry_path and return
    end
    
    @condition_report = VehicleConditionReport.new(
      vehicle: @vehicle,
      security_gate_officer: current_user
    )
    
    @driver_name = session[:driver_name]
    @driver_id = session[:driver_id]
    @notes = session[:notes]
    @client_type = session[:client_type]
    @agency_id = session[:agency_id]
    @client_params = session[:client_params]
    
    response.headers["Cache-Control"] = "no-cache, no-store, must-revalidate, max-age=0"
    response.headers["Pragma"] = "no-cache"
    response.headers["Expires"] = "Mon, 01 Jan 1990 00:00:00 GMT"
    
    render layout: 'application'
  end
  
  # 🔥 UPDATED: submit_condition - Creates condition report FIRST, then reception log linked to it
  def submit_condition
    if params[:vehicle_id].present?
      @vehicle = Vehicle.find(params[:vehicle_id])
    elsif session[:check_in_vehicle_id].present?
      @vehicle = Vehicle.find(session[:check_in_vehicle_id])
    else
      flash[:alert] = "No vehicle selected. Please start over."
      redirect_to vmcott_security_gate_officer_manual_entry_path and return
    end
    
    if params[:signature_data].blank?
      flash[:alert] = "Driver signature is required."
      redirect_to vmcott_security_gate_officer_condition_check_path(@vehicle.id) and return
    end
    
    begin
      ActiveRecord::Base.transaction do
        # STEP 1: Create the Condition Report FIRST (this gets the ID)
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
        
        condition_data = {
          exterior_damage: Array(params[:exterior]).reject(&:blank?),
          exterior_notes: params[:exterior_notes],
          interior_issues: Array(params[:interior]).reject(&:blank?),
          tire_status: params[:tire_status] || 'good',
          tire_notes: params[:tire_notes],
          warning_lights: Array(params[:warnings]).reject(&:blank?),
          additional_notes: params[:notes]
        }
        @condition_report.condition_data = condition_data
        
        @condition_report.acknowledgment = {
          driver_name: params[:driver_name],
          driver_id_number: params[:driver_id_number],
          signature_data: params[:signature_data],
          signed_at: Time.current,
          ip_address: request.remote_ip,
          user_agent: request.user_agent
        }
        
        unless @condition_report.save
          raise "Error saving condition report: #{@condition_report.errors.full_messages.join(', ')}"
        end
        
        # STEP 2: Attach photos to condition report
        attach_photos(@condition_report, params)
        
        # STEP 3: Create Reception Log LINKED to the condition report ID
        reception_log = ReceptionLog.create!(
          vehicle: @vehicle,
          user_id: current_user.id,
          driver_name: params[:driver_name],
          received_at: Time.current,
          check_in_time: Time.current,
          visitor_name: params[:driver_name],
          notes: params[:notes],
          status: 'checked_in',
          condition_report_id: @condition_report.id,  # 🔥 CRITICAL: Link to condition report
          condition_status: condition_data[:exterior_damage].present? && condition_data[:exterior_damage].any? ? 'damage_noted' : 'clean'
        )
        
        Rails.logger.info "✅ Created condition report ##{@condition_report.id} and linked reception log ##{reception_log.id}"
        
        # STEP 4: Create vehicle status
        VehicleStatus.create!(
          vehicle: @vehicle,
          created_by: current_user,
          status: 'vehicle_received',
          current: true,
          notes: "Vehicle received from #{params[:driver_name]}. Condition: #{condition_data[:exterior_damage].present? && condition_data[:exterior_damage].any? ? 'Damage noted' : 'Clean'}"
        )
        
        # STEP 5: Clear session
        clear_check_in_session
        
        # STEP 6: Notify inspectors
        notify_inspectors(@vehicle, @condition_report)
        
        flash[:notice] = "Vehicle #{@vehicle.license_plate} checked in successfully. Condition Report ##{@condition_report.id} created and linked to Reception Log."
        redirect_to vmcott_security_gate_officer_dashboard_path
      end
    rescue => e
      Rails.logger.error "Error in submit_condition: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      flash[:alert] = "An error occurred: #{e.message}"
      redirect_to vmcott_security_gate_officer_condition_check_path(@vehicle.id)
    end
  end
  
  def reception_logs
    @logs = ReceptionLog.includes(:vehicle, :security_gate_officer, :condition_report)
                        .order(received_at: :desc)
                        .page(params[:page])
                        .per(20)
    
    response.headers["Cache-Control"] = "no-cache, no-store, must-revalidate, max-age=0"
    response.headers["Pragma"] = "no-cache"
    response.headers["Expires"] = "Mon, 01 Jan 1990 00:00:00 GMT"
    
    render layout: 'application'
  end
  
  def show_reception_log
    @log = ReceptionLog.includes(:vehicle, :security_gate_officer, :condition_report, :inspector)
                       .find(params[:id])
    
    response.headers["Cache-Control"] = "no-cache, no-store, must-revalidate, max-age=0"
    response.headers["Pragma"] = "no-cache"
    response.headers["Expires"] = "Mon, 01 Jan 1990 00:00:00 GMT"
    
    render layout: 'application'
  end
  
  def today_logs
    @logs = ReceptionLog.includes(:vehicle, :security_gate_officer)
                        .where(received_at: Date.current.all_day)
                        .order(received_at: :desc)
    
    response.headers["Cache-Control"] = "no-cache, no-store, must-revalidate, max-age=0"
    response.headers["Pragma"] = "no-cache"
    response.headers["Expires"] = "Mon, 01 Jan 1990 00:00:00 GMT"
    
    render layout: 'application'
  end
  
  private
  
  def require_security_gate_officer
    unless current_user.security_gate_officer? || current_user.admin?
      Rails.logger.error "ACCESS DENIED - User: #{current_user.email}, Role: #{current_user.role}"
      redirect_to root_path, alert: "Access denied. Security Gate Officer privileges required."
    end
  end
  
  def disable_caching
    response.headers["Cache-Control"] = "no-cache, no-store, must-revalidate, max-age=0"
    response.headers["Pragma"] = "no-cache"
    response.headers["Expires"] = "Mon, 01 Jan 1990 00:00:00 GMT"
  end
  
  def new_vehicle_params
    params.require(:new_vehicle).permit(
      :license_plate, :make, :model, :year_of_manufacture, :color,
      :vehicle_type, :chassis_number, :serial_number,
      :engine_number
    )
  end
  
  def attach_photos(report, params)
    %w[front rear left right dashboard odometer fuel damage].each do |photo_type|
      param_key = "photo_#{photo_type}".to_sym
      if params[param_key].present? && params[param_key].respond_to?(:read)
        report.condition_photos.attach(
          io: params[param_key],
          filename: "#{photo_type}_#{Time.current.to_i}.jpg",
          content_type: params[param_key].content_type
        )
      end
    end
  end
  
  def notify_inspectors(vehicle, condition_report)
    return unless defined?(Notification)
    
    inspector_ids = User.where(role: 'inspector').pluck(:id)
    return if inspector_ids.empty?
    
    Notification.create!(
      title: "Vehicle Ready for Inspection",
      message: "#{vehicle.license_plate} received. #{condition_report.exterior_damage? ? 'Damage noted' : 'No damage'}",
      link: vmcott_inspector_pre_inspection_path(vehicle.id),
      user_id: inspector_ids,
      notifiable_type: 'Vehicle',
      notifiable_id: vehicle.id
    )
  rescue => e
    Rails.logger.error "Failed to create notification: #{e.message}"
  end
  
  def clear_check_in_session
    session.delete(:check_in_vehicle_id)
    session.delete(:driver_name)
    session.delete(:driver_id)
    session.delete(:notes)
    session.delete(:client_type)
    session.delete(:agency_id)
    session.delete(:client_params)
    session.delete(:new_vehicle_params)
  end
  
  def create_vehicle_from_session
    return nil unless session[:new_vehicle_params].present?
    
    owner = nil
    client_type = session[:client_type]
    
    if client_type == 'agency' && session[:agency_id].present?
      owner = Agency.find(session[:agency_id])
    elsif client_type == 'walkin' && session[:client_params].present?
      client_params = session[:client_params]
      raw_phone = client_params[:phone].to_s.strip
      phone = raw_phone.gsub(/[^0-9]/, '')
      owner = Client.find_or_initialize_by(phone: phone)
      
      if owner.new_record?
        owner.assign_attributes(
          name: client_params[:name].to_s.strip,
          email: client_params[:email].to_s.strip.presence,
          address: client_params[:address].to_s.strip.presence,
          client_type: 'individual',
          payment_terms: 'cash',
          is_active: true
        )
        owner.save!
      end
    elsif client_type == 'new_company' && session[:client_params].present?
      client_params = session[:client_params]
      raw_phone = client_params[:phone].to_s.strip
      phone = raw_phone.gsub(/[^0-9]/, '')
      owner = Client.find_or_initialize_by(phone: phone)
      
      if owner.new_record?
        owner.assign_attributes(
          name: "#{client_params[:name].to_s.strip} - #{client_params[:contact_person].to_s.strip}",
          email: client_params[:email].to_s.strip,
          address: client_params[:address].to_s.strip,
          client_type: 'corporate',
          payment_terms: client_params[:payment_terms],
          is_active: true
        )
        owner.save!
      end
    end
    
    vehicle = Vehicle.new(session[:new_vehicle_params])
    vehicle.owner = owner
    vehicle.skip_optional_validation = true
    
    unless vehicle.save
      raise "Could not create vehicle from session: #{vehicle.errors.full_messages.join(', ')}"
    end
    
    vehicle
  end
  
  def search_vehicles
    query = params[:q].to_s.strip
    
    if query.length < 2
      render json: [] and return
    end
    
    vehicles = Vehicle.includes(:owner)
                      .search(query)
                      .limit(10)
                      .map do |v|
      {
        id: v.id,
        license_plate: v.license_plate,
        make: v.make,
        model: v.model,
        owner_type: v.owner_type,
        owner_name: v.owner_name,
        agency_code: v.owner.is_a?(Agency) ? v.owner.code : nil,
        display: "#{v.license_plate} - #{v.make} #{v.model}"
      }
    end
    
    render json: vehicles
  end
end