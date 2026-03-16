# app/controllers/vmcott/security_gate_officer/dashboard_controller.rb
class Vmcott::SecurityGateOfficer::DashboardController < ApplicationController
  # Skip the dashboard caching for this controller - THIS IS THE FIX!
  skip_around_action :cache_dashboard_data, if: :dashboard_controller?
  
  before_action :authenticate_user!
  before_action :require_security_gate_officer
  # Optional: Keep debug logging if you want - remove if not needed
  before_action :log_debug_info, only: [:index, :manual_entry]
  
  # Disable all caching for this controller
  before_action :disable_caching

  def index
    log_section("DASHBOARD INDEX START") if respond_to?(:log_section)
    
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
    
    # Stats hash for the view - THIS IS CRITICAL
    @stats = {
      today_checkins: @today_checkins,
      vehicles_on_site: @vehicles_on_site,
      pending_reports: @pending_condition_reports
    }
    
    log_debug_variables if respond_to?(:log_debug_variables)
    log_section("DASHBOARD INDEX END") if respond_to?(:log_section)
    
    # Set headers to prevent caching
    response.headers["Cache-Control"] = "no-cache, no-store, must-revalidate, max-age=0"
    response.headers["Pragma"] = "no-cache"
    response.headers["Expires"] = "Mon, 01 Jan 1990 00:00:00 GMT"
    
    # Render with default application layout
    render layout: 'application'
  end
  
  def scan
    log_section("SCAN ACTION") if respond_to?(:log_section)
    # Disable caching
    response.headers["Cache-Control"] = "no-cache, no-store, must-revalidate, max-age=0"
    response.headers["Pragma"] = "no-cache"
    response.headers["Expires"] = "Mon, 01 Jan 1990 00:00:00 GMT"
    
    # Renders QR code scanner view
    render layout: 'application'
  end
  
  def manual_entry
    log_section("MANUAL ENTRY START") if respond_to?(:log_section)
    
    @agencies = Agency.where(code: ['PTSC', 'TTPS', 'TTDF', 'VMCOTT']).order(:name)
    @allow_new_vehicle = true
    @is_new_vehicle_mode = params[:create_new_vehicle] == 'true'
    
    Rails.logger.info "Agencies found: #{@agencies.count}" if Rails.env.development?
    Rails.logger.info "New vehicle mode: #{@is_new_vehicle_mode}" if Rails.env.development?
    
    log_section("MANUAL ENTRY END") if respond_to?(:log_section)
    
    # Disable caching
    response.headers["Cache-Control"] = "no-cache, no-store, must-revalidate, max-age=0"
    response.headers["Pragma"] = "no-cache"
    response.headers["Expires"] = "Mon, 01 Jan 1990 00:00:00 GMT"
    
    render layout: 'application'
  end
  
  def receive_vehicle
    log_section("RECEIVE VEHICLE START") if respond_to?(:log_section)
    Rails.logger.info "Params: #{params.except(:authenticity_token).inspect}" if Rails.env.development?
    
    begin
      ActiveRecord::Base.transaction do
        vehicle = nil
        owner = nil
        
        # Get client type from form (new field)
        client_type = params[:selected_client_type]
        
        # Validate client type was selected
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
          
          # Determine owner based on client type
          if client_type == 'agency'
            # AGENCY
            if params[:agency_id].blank?
              flash[:alert] = "Please select an agency"
              redirect_to vmcott_security_gate_officer_manual_entry_path(create_new_vehicle: true) and return
            end
            owner = Agency.find(params[:agency_id])
            Rails.logger.info "Owner is agency: #{owner.code}" if Rails.env.development?
            
          elsif client_type == 'walkin'
            # WALK-IN CUSTOMER
            if params[:walkin][:name].blank?
              flash[:alert] = "Customer name is required"
              redirect_to vmcott_security_gate_officer_manual_entry_path(create_new_vehicle: true) and return
            end
            if params[:walkin][:phone].blank?
              flash[:alert] = "Phone number is required"
              redirect_to vmcott_security_gate_officer_manual_entry_path(create_new_vehicle: true) and return
            end
            
            # Clean the phone number
            phone = params[:walkin][:phone].to_s.strip.gsub(/[^0-9]/, '')
            
            # Create walk-in client
            owner = Client.create!(
              name: params[:walkin][:name].to_s.strip,
              phone: phone,
              email: params[:walkin][:email].to_s.strip.presence,
              address: params[:walkin][:address].to_s.strip.presence,
              id_number: params[:walkin][:id_number].to_s.strip.presence,
              client_type: 'individual',
              payment_terms: 'cash_on_pickup',
              is_active: true
            )
            Rails.logger.info "Created walk-in client: #{owner.name}" if Rails.env.development?
            
          elsif client_type == 'new_company'
            # NEW COMPANY
            # Validate required fields
            if params[:company][:name].blank?
              flash[:alert] = "Company name is required"
              redirect_to vmcott_security_gate_officer_manual_entry_path(create_new_vehicle: true) and return
            end
            if params[:company][:contact_person].blank?
              flash[:alert] = "Contact person is required"
              redirect_to vmcott_security_gate_officer_manual_entry_path(create_new_vehicle: true) and return
            end
            if params[:company][:phone].blank?
              flash[:alert] = "Phone number is required"
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
            
            # Clean the phone number
            phone = params[:company][:phone].to_s.strip.gsub(/[^0-9]/, '')
            
            # Create new company client
            owner = Client.create!(
              name: params[:company][:name].to_s.strip,
              contact_person: params[:company][:contact_person].to_s.strip,
              phone: phone,
              email: params[:company][:email].to_s.strip,
              address: params[:company][:address].to_s.strip,
              registration_number: params[:company][:registration].to_s.strip.presence,
              client_type: 'corporate',
              payment_terms: params[:company][:payment_terms],
              is_active: true
            )
            Rails.logger.info "Created new company: #{owner.name}" if Rails.env.development?
          end
          
          # Create the vehicle using new_vehicle_params
          vehicle = Vehicle.new(new_vehicle_params)
          vehicle.owner = owner
          
          # Set a flag to skip validation for optional fields
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
        
        # Store client-specific data based on type
        if client_type == 'agency'
          session[:agency_id] = params[:agency_id]
        elsif client_type == 'walkin'
          session[:client_params] = {
            name: params[:walkin][:name],
            phone: params[:walkin][:phone],
            email: params[:walkin][:email],
            address: params[:walkin][:address],
            id_number: params[:walkin][:id_number],
            payment_terms: 'cash_on_pickup'
          }
        elsif client_type == 'new_company'
          session[:client_params] = {
            name: params[:company][:name],
            contact_person: params[:company][:contact_person],
            phone: params[:company][:phone],
            email: params[:company][:email],
            address: params[:company][:address],
            registration: params[:company][:registration],
            payment_terms: params[:company][:payment_terms]
          }
        end
        
        # Store new vehicle params in session if this was a new vehicle
        if params[:new_vehicle].present?
          session[:new_vehicle_params] = new_vehicle_params.to_h
        end
        
        Rails.logger.info "Session stored with vehicle_id: #{vehicle.id}" if Rails.env.development?
        log_section("RECEIVE VEHICLE END - SUCCESS") if respond_to?(:log_section)
        
        # Redirect to condition check form
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
    log_section("CONDITION CHECK START") if respond_to?(:log_section)
    
    # Handle different ways vehicle_id might be passed
    if params[:vehicle_id].present?
      @vehicle = Vehicle.find(params[:vehicle_id])
      Rails.logger.info "Found vehicle by params: #{@vehicle.license_plate}" if Rails.env.development?
    elsif session[:check_in_vehicle_id].present?
      @vehicle = Vehicle.find(session[:check_in_vehicle_id])
      Rails.logger.info "Found vehicle by session: #{@vehicle.license_plate}" if Rails.env.development?
    elsif params[:create_new_vehicle] == 'true' && session[:new_vehicle_params].present?
      Rails.logger.info "Creating vehicle from session" if Rails.env.development?
      @vehicle = create_vehicle_from_session
    else
      flash[:alert] = "No vehicle selected. Please start the check-in process."
      redirect_to vmcott_security_gate_officer_manual_entry_path and return
    end
    
    # Check if we have a pending check-in
    if session[:check_in_vehicle_id].present? && session[:check_in_vehicle_id].to_i != @vehicle.id
      Rails.logger.error "Session mismatch: session=#{session[:check_in_vehicle_id]}, vehicle=#{@vehicle.id}"
      flash[:alert] = "Session mismatch. Please start over."
      redirect_to vmcott_security_gate_officer_manual_entry_path and return
    end
    
    # Initialize a new condition report
    @condition_report = VehicleConditionReport.new(
      vehicle: @vehicle,
      security_gate_officer: current_user
    )
    
    # Pre-fill from session if available
    @driver_name = session[:driver_name]
    @driver_id = session[:driver_id]
    @notes = session[:notes]
    
    # Store client info in session for later use
    @client_type = session[:client_type]
    @agency_id = session[:agency_id]
    @client_params = session[:client_params]
    
    log_section("CONDITION CHECK END") if respond_to?(:log_section)
    
    # Disable caching
    response.headers["Cache-Control"] = "no-cache, no-store, must-revalidate, max-age=0"
    response.headers["Pragma"] = "no-cache"
    response.headers["Expires"] = "Mon, 01 Jan 1990 00:00:00 GMT"
    
    render layout: 'application'
  end
  
  def submit_condition
    log_section("SUBMIT CONDITION START") if respond_to?(:log_section)
    
    # Determine which vehicle we're working with
    if params[:vehicle_id].present?
      @vehicle = Vehicle.find(params[:vehicle_id])
    elsif params[:create_new_vehicle] == 'true' && params[:new_vehicle].present?
      # Handle creating a new vehicle right here in condition check
      @vehicle = create_vehicle_from_params(params[:new_vehicle], params)
    elsif session[:check_in_vehicle_id].present?
      @vehicle = Vehicle.find(session[:check_in_vehicle_id])
    else
      flash[:alert] = "No vehicle selected. Please start over."
      redirect_to vmcott_security_gate_officer_manual_entry_path and return
    end
    
    # Verify session (if we have one)
    if session[:check_in_vehicle_id].present? && session[:check_in_vehicle_id].to_i != @vehicle.id
      flash[:alert] = "Session expired. Please start over."
      redirect_to vmcott_security_gate_officer_manual_entry_path and return
    end
    
    # Validate signature
    if params[:signature_data].blank?
      flash[:alert] = "Driver signature is required."
      redirect_to vmcott_security_gate_officer_condition_check_path(@vehicle.id) and return
    end
    
    begin
      ActiveRecord::Base.transaction do
        # Determine client for reference (not saved to reception_log)
        client = determine_client_from_params(params)
        
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
        
        # Handle acknowledgment
        @condition_report.acknowledgment = {
          driver_name: params[:driver_name],
          driver_id_number: params[:driver_id_number],
          signature_data: params[:signature_data],
          signed_at: Time.current,
          ip_address: request.remote_ip,
          user_agent: request.user_agent
        }
        
        # Save the report
        unless @condition_report.save
          raise "Error saving condition report: #{@condition_report.errors.full_messages.join(', ')}"
        end
        
        # Attach photos if any
        attach_photos(@condition_report, params)
        
        # Create reception log
        ReceptionLog.create!(
          vehicle: @vehicle,
          user_id: current_user.id,
          driver_name: params[:driver_name],
          received_at: Time.current,
          check_in_time: Time.current,
          visitor_name: params[:driver_name],
          notes: params[:notes],
          status: 'checked_in',
          condition_report: @condition_report,
          condition_status: @condition_report.exterior_damage? ? 'damage_noted' : 'clean'
        )
        
        # Create vehicle status
        VehicleStatus.create!(
          vehicle: @vehicle,
          created_by: current_user,
          status: 'vehicle_received',
          current: true,
          notes: "Vehicle received from #{params[:driver_name]}. Condition: #{@condition_report.exterior_damage? ? 'Damage noted' : 'Clean'}"
        )
        
        # Clear session
        clear_check_in_session
        
        # Notify inspectors
        notify_inspectors(@vehicle, @condition_report)
        
        flash[:notice] = "Vehicle #{@vehicle.license_plate} checked in successfully."
        log_section("SUBMIT CONDITION END - SUCCESS") if respond_to?(:log_section)
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
    log_section("RECEPTION LOGS") if respond_to?(:log_section)
    @logs = ReceptionLog.includes(:vehicle, :security_gate_officer, :condition_report)
                        .order(received_at: :desc)
                        .page(params[:page])
                        .per(20)
    
    # Disable caching
    response.headers["Cache-Control"] = "no-cache, no-store, must-revalidate, max-age=0"
    response.headers["Pragma"] = "no-cache"
    response.headers["Expires"] = "Mon, 01 Jan 1990 00:00:00 GMT"
    
    render layout: 'application'
  end
  
  def show_reception_log
    @log = ReceptionLog.includes(:vehicle, :security_gate_officer, :condition_report, :inspector)
                       .find(params[:id])
    
    # Disable caching
    response.headers["Cache-Control"] = "no-cache, no-store, must-revalidate, max-age=0"
    response.headers["Pragma"] = "no-cache"
    response.headers["Expires"] = "Mon, 01 Jan 1990 00:00:00 GMT"
    
    render layout: 'application'
  end
  
  def today_logs
    @logs = ReceptionLog.includes(:vehicle, :security_gate_officer)
                        .where(received_at: Date.current.all_day)
                        .order(received_at: :desc)
    
    # Disable caching
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
  
  # Add this method to disable caching for all actions
  def disable_caching
    response.headers["Cache-Control"] = "no-cache, no-store, must-revalidate, max-age=0"
    response.headers["Pragma"] = "no-cache"
    response.headers["Expires"] = "Mon, 01 Jan 1990 00:00:00 GMT"
  end
  
  # Debug logging methods - keep for development, remove in production if desired
  def log_debug_info
    return unless Rails.env.development?
    
    Rails.logger.info "=" * 80
    Rails.logger.info "CONTROLLER: Vmcott::SecurityGateOfficer::DashboardController"
    Rails.logger.info "ACTION: #{action_name}"
    Rails.logger.info "USER: #{current_user&.email} (ID: #{current_user&.id})"
    Rails.logger.info "USER ROLE: #{current_user&.role}"
    Rails.logger.info "USER AGENCY: #{current_user&.agency&.code}"
    Rails.logger.info "security_gate_officer?: #{current_user&.security_gate_officer?}"
    Rails.logger.info "REQUEST PATH: #{request.path}"
    Rails.logger.info "REQUEST METHOD: #{request.method}"
    Rails.logger.info "PARAMS: #{params.except(:authenticity_token, :controller, :action).inspect}"
    Rails.logger.info "SESSION: #{session.to_hash.select { |k| k.to_s.include?('vehicle') || k.to_s.include?('client') }.inspect}"
  end
  
  def log_section(title)
    return unless Rails.env.development?
    Rails.logger.info "-" * 40
    Rails.logger.info title
    Rails.logger.info "-" * 40
  end
  
  def log_debug_variables
    return unless Rails.env.development?
    Rails.logger.info "INSTANCE VARIABLES:"
    Rails.logger.info "  @today_checkins: #{@today_checkins}"
    Rails.logger.info "  @vehicles_on_site: #{@vehicles_on_site}"
    Rails.logger.info "  @pending_condition_reports: #{@pending_condition_reports}"
    Rails.logger.info "  @recent_checkins count: #{@recent_checkins&.count || 0}"
    Rails.logger.info "  @stats: #{@stats.inspect}"
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
  
  # Helper method to determine client from params or session
  def determine_client_from_params(params)
    client = nil
    
    # First check params
    if params[:client_type] == 'agency' && params[:agency_id].present?
      client = Agency.find(params[:agency_id])
    elsif params[:client_type] == 'walkin' && params[:walkin].present?
      client_params = params[:walkin]
      phone = client_params[:phone].to_s.strip.gsub(/[^0-9]/, '')
      client = Client.find_or_initialize_by(phone: phone)
      
      if client.new_record?
        client.assign_attributes(
          name: client_params[:name].to_s.strip,
          email: client_params[:email].to_s.strip.presence,
          address: client_params[:address].to_s.strip.presence,
          id_number: client_params[:id_number].to_s.strip.presence,
          client_type: 'individual',
          payment_terms: 'cash_on_pickup',
          is_active: true
        )
        client.save!
      end
    elsif params[:client_type] == 'new_company' && params[:company].present?
      client_params = params[:company]
      phone = client_params[:phone].to_s.strip.gsub(/[^0-9]/, '')
      client = Client.find_or_initialize_by(phone: phone)
      
      if client.new_record?
        client.assign_attributes(
          name: client_params[:name].to_s.strip,
          contact_person: client_params[:contact_person].to_s.strip,
          email: client_params[:email].to_s.strip,
          address: client_params[:address].to_s.strip,
          registration_number: client_params[:registration].to_s.strip.presence,
          client_type: 'corporate',
          payment_terms: client_params[:payment_terms],
          is_active: true
        )
        client.save!
      end
    # Then check session
    elsif session[:client_type] == 'agency' && session[:agency_id].present?
      client = Agency.find(session[:agency_id])
    elsif session[:client_type] == 'walkin' && session[:client_params].present?
      client_params = session[:client_params]
      phone = client_params[:phone].to_s.strip.gsub(/[^0-9]/, '')
      client = Client.find_or_initialize_by(phone: phone)
      
      if client.new_record?
        client.assign_attributes(
          name: client_params[:name].to_s.strip,
          email: client_params[:email].to_s.strip.presence,
          address: client_params[:address].to_s.strip.presence,
          id_number: client_params[:id_number].to_s.strip.presence,
          client_type: 'individual',
          payment_terms: 'cash_on_pickup',
          is_active: true
        )
        client.save!
      end
    elsif session[:client_type] == 'new_company' && session[:client_params].present?
      client_params = session[:client_params]
      phone = client_params[:phone].to_s.strip.gsub(/[^0-9]/, '')
      client = Client.find_or_initialize_by(phone: phone)
      
      if client.new_record?
        client.assign_attributes(
          name: client_params[:name].to_s.strip,
          contact_person: client_params[:contact_person].to_s.strip,
          email: client_params[:email].to_s.strip,
          address: client_params[:address].to_s.strip,
          registration_number: client_params[:registration].to_s.strip.presence,
          client_type: 'corporate',
          payment_terms: client_params[:payment_terms],
          is_active: true
        )
        client.save!
      end
    end
    
    client
  end
  
  # Helper method to create a vehicle from params (for direct creation in condition check)
  def create_vehicle_from_params(vehicle_params, all_params)
    owner = nil
    client_type = all_params[:client_type]
    
    # Determine owner based on client type
    if client_type == 'agency' && all_params[:agency_id].present?
      owner = Agency.find(all_params[:agency_id])
    elsif client_type == 'walkin' && all_params[:walkin].present?
      client_params = all_params[:walkin]
      phone = client_params[:phone].to_s.strip.gsub(/[^0-9]/, '')
      owner = Client.find_or_initialize_by(phone: phone)
      
      if owner.new_record?
        owner.assign_attributes(
          name: client_params[:name].to_s.strip,
          email: client_params[:email].to_s.strip.presence,
          address: client_params[:address].to_s.strip.presence,
          id_number: client_params[:id_number].to_s.strip.presence,
          client_type: 'individual',
          payment_terms: 'cash_on_pickup',
          is_active: true
        )
        owner.save!
      end
    elsif client_type == 'new_company' && all_params[:company].present?
      client_params = all_params[:company]
      phone = client_params[:phone].to_s.strip.gsub(/[^0-9]/, '')
      owner = Client.find_or_initialize_by(phone: phone)
      
      if owner.new_record?
        owner.assign_attributes(
          name: client_params[:name].to_s.strip,
          contact_person: client_params[:contact_person].to_s.strip,
          email: client_params[:email].to_s.strip,
          address: client_params[:address].to_s.strip,
          registration_number: client_params[:registration].to_s.strip.presence,
          client_type: 'corporate',
          payment_terms: client_params[:payment_terms],
          is_active: true
        )
        owner.save!
      end
    end
    
    # Create vehicle
    vehicle = Vehicle.new(vehicle_params)
    vehicle.owner = owner
    
    # Make optional fields not required
    vehicle.skip_optional_validation = true
    
    unless vehicle.save
      raise "Could not create vehicle: #{vehicle.errors.full_messages.join(', ')}"
    end
    
    vehicle
  end
  
  # Helper method to create vehicle from session (for condition check when vehicle wasn't pre-selected)
  def create_vehicle_from_session
    return nil unless session[:new_vehicle_params].present?
    
    owner = nil
    client_type = session[:client_type]
    
    # Determine owner from session
    if client_type == 'agency' && session[:agency_id].present?
      owner = Agency.find(session[:agency_id])
    elsif client_type == 'walkin' && session[:client_params].present?
      client_params = session[:client_params]
      phone = client_params[:phone].to_s.strip.gsub(/[^0-9]/, '')
      owner = Client.find_or_initialize_by(phone: phone)
      
      if owner.new_record?
        owner.assign_attributes(
          name: client_params[:name].to_s.strip,
          email: client_params[:email].to_s.strip.presence,
          address: client_params[:address].to_s.strip.presence,
          id_number: client_params[:id_number].to_s.strip.presence,
          client_type: 'individual',
          payment_terms: 'cash_on_pickup',
          is_active: true
        )
        owner.save!
      end
    elsif client_type == 'new_company' && session[:client_params].present?
      client_params = session[:client_params]
      phone = client_params[:phone].to_s.strip.gsub(/[^0-9]/, '')
      owner = Client.find_or_initializeBy(phone: phone)
      
      if owner.new_record?
        owner.assign_attributes(
          name: client_params[:name].to_s.strip,
          contact_person: client_params[:contact_person].to_s.strip,
          email: client_params[:email].to_s.strip,
          address: client_params[:address].to_s.strip,
          registration_number: client_params[:registration].to_s.strip.presence,
          client_type: 'corporate',
          payment_terms: client_params[:payment_terms],
          is_active: true
        )
        owner.save!
      end
    end
    
    # Create vehicle
    vehicle = Vehicle.new(session[:new_vehicle_params])
    vehicle.owner = owner
    
    # Make optional fields not required
    vehicle.skip_optional_validation = true
    
    unless vehicle.save
      raise "Could not create vehicle from session: #{vehicle.errors.full_messages.join(', ')}"
    end
    
    vehicle
  end
  
  # API endpoint for vehicle search (used by the condition check form)
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