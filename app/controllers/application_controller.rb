# app/controllers/application_controller.rb
class ApplicationController < ActionController::Base
  include Pundit::Authorization
  
  # Only allow modern browsers supporting essential features
  allow_browser versions: :modern
  
  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  # IMPORTANT: CSRF protection configuration
  protect_from_forgery with: :exception, prepend: true
  
  # Devise controllers handle their own CSRF protection
  skip_before_action :verify_authenticity_token, if: :devise_controller?

  # =====================================================
  # Authentication
  # =====================================================
  before_action :authenticate_user!

  # =====================================================
  # Callbacks
  # =====================================================
  before_action :set_current_user
  before_action :set_current_request
  before_action :set_timezone
  before_action :check_for_turbo_frame
  before_action :set_agency_theme
  before_action :prevent_real_payments_in_dev
  before_action :set_notification_counts, if: :user_signed_in?
  before_action :set_screensaver_skip  # NEW: Skip screensaver on certain pages
  
  # Set Current context for POS transactions
  around_action :set_current_context
  # POS transaction current user setup
  around_action :set_pos_transaction_current_user, unless: :skip_pos_transaction_callback?
  
  # NEW: Dashboard data caching
  around_action :cache_dashboard_data, if: :dashboard_controller?

  # =====================================================
  # AFTER SIGN OUT
  # =====================================================
  def after_sign_out_path_for(resource_or_scope)
    flash.clear
    root_path
  end

  # =====================================================
  # AFTER SIGN IN REDIRECT - UPDATED WITH NEW ROLE NAMES
  # =====================================================
  def after_sign_in_path_for(resource)
    # Debug logging
    Rails.logger.info "=== AFTER SIGN IN REDIRECT ==="
    
    # Handle case where resource might be an array
    user = if resource.is_a?(Array)
            Rails.logger.info "Resource is an array: #{resource.inspect}"
            resource.find { |r| r.respond_to?(:email) }
          else
            resource
          end
    
    # Check if we have a valid user object
    if user.nil? || !user.respond_to?(:email)
      Rails.logger.error "No valid user object found. Resource: #{resource.inspect}"
      return main_dashboard_path
    end
    
    Rails.logger.info "User: #{user.email}"
    Rails.logger.info "Agency: #{user.agency.inspect}"
    Rails.logger.info "Agency Code: #{user.agency&.code}"
    Rails.logger.info "Role: #{user.role}"
    Rails.logger.info "=============================="

    # ============================================
    # VMCOTT ROLE-BASED DASHBOARDS (UPDATED WITH NEW ROLE NAMES)
    # ============================================
    if user.agency&.code == 'VMCOTT'
      case user.role
      when 'security_gate_officer'  # was 'receptionist'
        return vmcott_security_gate_officer_dashboard_path
      when 'inspector'
        return vmcott_inspector_dashboard_path
      when 'inventory_manager'      # was 'parts_coordinator'
        return vmcott_inventory_manager_dashboard_path
      when 'mechanic'
        return vmcott_mechanic_dashboard_path
      when 'procurement'            # was 'billing'
        return vmcott_procurement_dashboard_path
      when 'finance'
        return vmcott_finance_dashboard_path
      when 'maintenance_supervisor', 'workshop_supervisor'
        return vmcott_workshop_supervisor_dashboard_path
      when 'admin'
        return vmcott_dashboard_path
      else
        # Fallback for any other VMCOTT staff
        Rails.logger.warn "Unknown VMCOTT role: #{user.role}, redirecting to main dashboard"
        return vmcott_dashboard_path
      end
    end

    # ============================================
    # PTSC ROLE-BASED DASHBOARDS
    # ============================================
    if user.agency&.code == 'PTSC'
      case user.role
      when 'fleet_manager'
        return ptsc_fleet_dashboard_path
      when 'finance'
        return ptsc_finance_dashboard_path
      when 'driver'
        return ptsc_driver_dashboard_path
      when 'maintenance_supervisor', 'maintenance'
        return ptsc_maintenance_dashboard_path
      when 'admin'
        return ptsc_dashboard_path
      else
        return ptsc_dashboard_path
      end
    end

    # ============================================
    # OTHER AGENCY DASHBOARDS
    # ============================================
    case user.agency&.code
    when "TTPS"
      return ttps_dashboard_path
    when "TTDF"
      return ttdf_dashboard_path
    when "FIRE"
      return fire_dashboard_path if respond_to?(:fire_dashboard_path)
    when "HEALTH"
      return health_dashboard_path if respond_to?(:health_dashboard_path)
    when "EDUCATION"
      return education_dashboard_path if respond_to?(:education_dashboard_path)
    end

    # ============================================
    # FALLBACK
    # ============================================
    case user.role
    when 'admin'
      main_dashboard_path
    when 'fleet_manager'
      if user.agency.present?
        agency_vehicles_path(user.agency)
      else
        main_dashboard_path
      end
    else
      main_dashboard_path
    end
  end

  # =====================================================
  # NOTIFICATION COUNTS FOR VMCOTT WORKFLOW ROLES - FIXED
  # =====================================================
  def set_notification_counts
    return unless current_user.present?
    
    # Initialize all variables to avoid nil errors
    @unread_notifications_count = 0
    @recent_notifications = []
    @pending_inspections_count = 0
    @qc_pending_count = 0
    @pending_parts_count = 0
    @pending_parts_review_count = 0
    @parts_received_count = 0
    @available_jobs_count = 0
    @my_assigned_jobs_count = 0
    @pending_quotations_count = 0
    @pending_rfqs_count = 0
    @ready_for_pickup_count = 0
    @pending_invoices_count = 0
    @overdue_jobs_count = 0
    @pending_supervisor_review_count = 0
    @alerts_count = 0
    @pending_parts_requests_count = 0
    @quotations_to_review_count = 0
    @pending_po_approval_count = 0
    @pending_condition_reports_count = 0
    @low_stock_alert_count = 0
    @parts_to_order_count = 0
    @qc_pending_inspections_count = 0
    @inspections_today_count = 0
    @assigned_jobs_count = 0
    @in_progress_count = 0
    @at_vmcott_count = 0
    @in_progress_count_ptsc = 0
    @ready_for_pickup_count_ptsc = 0
    @pending_rfq_responses_count = 0
    
    # General notifications for all users - FIXED WITH SAFE COLUMN DETECTION
    if defined?(Notification)
      begin
        # Safely detect which column exists
        if Notification.column_names.include?('read_at')
          # Use read_at: nil for unread notifications
          @unread_notifications_count = Notification.where(user: current_user, read_at: nil).count
          @recent_notifications = Notification.where(user: current_user)
                                              .where(read_at: nil)
                                              .order(created_at: :desc)
                                              .limit(5)
        elsif Notification.column_names.include?('read')
          # Use read: false for unread notifications
          @unread_notifications_count = Notification.where(user: current_user, read: false).count
          @recent_notifications = Notification.where(user: current_user)
                                              .where(read: false)
                                              .order(created_at: :desc)
                                              .limit(5)
        else
          # Fallback - count all notifications in the last 7 days
          @unread_notifications_count = Notification.where(user: current_user)
                                                    .where('created_at > ?', 7.days.ago)
                                                    .count
          @recent_notifications = Notification.where(user: current_user)
                                              .where('created_at > ?', 7.days.ago)
                                              .order(created_at: :desc)
                                              .limit(5)
        end
      rescue => e
        Rails.logger.error "Notification query error: #{e.message}"
        @unread_notifications_count = 0
        @recent_notifications = []
      end
    end
    
    # Role-specific counts for VMCOTT users - UPDATED WITH NEW ROLE NAMES
    if current_user.agency&.code == 'VMCOTT'
      
      # Security Gate Officer counts (was receptionist)
      if current_user.security_gate_officer? || current_user.admin?
        if defined?(VehicleConditionReport)
          @pending_condition_reports_count = VehicleConditionReport.where(agency_id: current_user.agency_id, status: 'pending').count rescue 0
        end
        if defined?(ReceptionLog)
          @inspections_today_count = ReceptionLog.where(agency_id: current_user.agency_id)
                                                .where('DATE(check_in_time) = ?', Date.current)
                                                .count rescue 0
        end
      end
      
      # Inspector counts
      if current_user.inspector? || current_user.admin?
        if defined?(Inspection)
          @pending_inspections_count = Inspection.where(agency_id: current_user.agency_id, status: 'pending_inspection').count rescue 0
          @qc_pending_inspections_count = Inspection.where(agency_id: current_user.agency_id, status: 'qc_pending').count rescue 0
          @qc_pending_count = Inspection.where(agency_id: current_user.agency_id, status: 'qc_pending').count rescue 0
          @inspections_today_count = Inspection.where(agency_id: current_user.agency_id)
                                              .where('DATE(created_at) = ?', Date.current)
                                              .count rescue 0
        end
      end
      
      # Inventory Manager counts (was parts_coordinator)
      if current_user.inventory_manager? || current_user.admin?
        if defined?(PartsRequest)
          @pending_parts_count = PartsRequest.where(status: 'pending').count rescue 0
          @pending_parts_review_count = PartsRequest.where(status: 'pending').count rescue 0
          @parts_received_count = PartsRequest.where(status: 'parts_received').count rescue 0
          @parts_to_order_count = PartsRequest.where(status: 'needs_order').count rescue 0
        end
        if defined?(Part)
          @low_stock_alert_count = Part.where('current_stock <= reorder_point').count rescue 0
        end
      end
      
      # Mechanic counts
      if current_user.mechanic? || current_user.admin?
        if defined?(InspectionJob)
          @available_jobs_count = InspectionJob.where(assigned_mechanic_id: nil, completed_at: nil)
                                              .where.not(inspection_id: Inspection.where(status: 'pending_inspection').select(:id))
                                              .count rescue 0
          @my_assigned_jobs_count = InspectionJob.where(assigned_mechanic_id: current_user.id, completed_at: nil).count rescue 0
          @assigned_jobs_count = InspectionJob.where(assigned_mechanic_id: current_user.id).count rescue 0
          @in_progress_count = InspectionJob.where(assigned_mechanic_id: current_user.id, status: 'in_progress').count rescue 0
        end
        @qc_pending_count = Inspection.where(agency_id: current_user.agency_id, status: 'qc_pending').count rescue 0
      end
      
      # Procurement counts (was billing)
      if current_user.procurement? || current_user.admin?
        if defined?(PartsRequest)
          @pending_parts_requests_count = PartsRequest.where(status: 'procurement_notified').count rescue 0
        end
        if defined?(VendorRfq)
          @pending_rfqs_count = VendorRfq.where(status: 'draft').count rescue 0
          @pending_rfq_responses_count = VendorRfq.where(status: 'quotations_received').count rescue 0
        end
      end
      
      # Finance counts
      if current_user.finance? || current_user.admin?
        if defined?(VendorQuotation)
          @quotations_to_review_count = VendorQuotation.where(status: 'received').count rescue 0
        end
        if defined?(PurchaseOrder)
          @pending_po_approval_count = PurchaseOrder.where(status: 'pending_approval').count rescue 0
        end
        if defined?(Inspection)
          @ready_for_pickup_count = Inspection.where(agency_id: current_user.agency_id, status: 'ready_for_pickup').count rescue 0
        end
        if defined?(Invoice)
          @pending_invoices_count = Invoice.where(status: 'pending').count rescue 0
        end
        if defined?(VendorRfq)
          @pending_rfq_responses_count = VendorRfq.where(status: 'quotations_received').count rescue 0
        end
      end
      
      # Workshop Supervisor counts
      if current_user.maintenance_supervisor? || current_user.admin?
        if defined?(InternalPos)
          @overdue_jobs_count = InternalPos.where('estimated_completion_date < ?', Date.today)
                                          .where.not(status: ['completed', 'cancelled'])
                                          .count rescue 0
        end
        @pending_supervisor_review_count = Inspection.where(agency_id: current_user.agency_id, status: 'qc_pending').count rescue 0
        if defined?(Vehicle)
          @at_vmcott_count = Vehicle.where(agency_id: current_user.agency_id, current_location: 'VMCOTT').count rescue 0
        end
      end
      
    elsif current_user.agency&.code == 'PTSC'
      # PTSC-specific counts
      if current_user.finance? || current_user.admin?
        if defined?(VendorRfq)
          @pending_rfq_responses_count = VendorRfq.where(processing_agency_id: current_user.agency_id, status: 'quotations_received').count rescue 0
        end
      end
      if current_user.fleet_manager? || current_user.admin? || current_user.maintenance_supervisor?
        if defined?(Vehicle)
          @at_vmcott_count = Vehicle.where(agency_id: current_user.agency_id, current_location: 'VMCOTT').count rescue 0
        end
        if defined?(InternalPos)
          @in_progress_count_ptsc = InternalPos.where(status: 'in_progress').count rescue 0
        end
        if defined?(Inspection)
          @ready_for_pickup_count_ptsc = Inspection.where(agency_id: current_user.agency_id, status: 'ready_for_pickup').count rescue 0
        end
      end
    else
      # Non-VMCOTT/PTSC users (agencies) see alerts
      if defined?(Alert)
        @alerts_count = Alert.where(agency_id: current_user.agency_id, status: 'active').count rescue 0
      end
    end
  rescue => e
    Rails.logger.error "Error in set_notification_counts: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    # Don't re-raise - we want the app to continue even if notifications fail
    # Set defaults to avoid nil errors
    @unread_notifications_count = 0
    @recent_notifications = []
  end

  # =====================================================
  # SCREENSAVER SETUP - UPDATED
  # =====================================================
  def set_screensaver_skip
    @skip_screensaver = params[:controller] == 'screensaver' || 
                        params[:controller] == 'home' ||
                        params[:controller] == 'devise/sessions' ||
                        params[:controller] == 'devise/passwords' ||
                        params[:controller] == 'devise/registrations'
  end

  # =====================================================
  # DASHBOARD CACHING - FIXED with Workshop Supervisor Skip
  # =====================================================
  def cache_dashboard_data
    # CRITICAL: Skip caching for Workshop Supervisor dashboard completely
    if controller_path == 'vmcott/workshop_supervisor/dashboard'
      Rails.logger.info "🚫 Skipping cache for Workshop Supervisor Dashboard - Preventing white screen"
      return yield
    end
    
    return yield unless current_user.present?
    
    # Skip caching for reception_logs controller and show actions
    if params[:controller].include?('reception_logs') || 
       params[:action] == 'show' ||
       params[:action] == 'today' ||
       params[:action] == 'condition_report'
      Rails.logger.info "Skipping cache for #{params[:controller]}##{params[:action]}"
      return yield
    end
    
    begin
      cache_key = "dashboard/#{current_user.role}/#{current_user.id}/#{Date.current.strftime('%Y%m%d')}"
      cache_key << "/#{params[:action]}" if params[:action].present?
      
      # Only cache for index/dashboard actions
      if params[:action].in?(['index', 'dashboard'])
        Rails.logger.info "Caching dashboard data with key: #{cache_key}"
        Rails.cache.fetch(cache_key, expires_in: 1.hour) do
          yield
        end
      else
        yield
      end
    rescue => e
      Rails.logger.error "Cache error: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      yield # Fall back to normal rendering
    end
  end
  
  def dashboard_controller?
    # Skip caching for workshop supervisor completely
    return false if controller_path == 'vmcott/workshop_supervisor/dashboard'
    
    controller_path.start_with?('vmcott/') && 
    params[:action].in?(['index', 'dashboard']) &&
    !params[:controller].include?('reception_logs') # Skip reception_logs controller
  end

  # =====================================================
  # Helper Methods - UPDATED WITH NEW ROLE NAMES AND SKIP_NAVIGATION
  # =====================================================
  helper_method :current_agency, 
                :admin?, 
                :manager?, 
                :vmcott?,
                :security_gate_officer?,  # was receptionist?
                :inspector?,
                :inventory_manager?,      # was parts_coordinator?
                :mechanic?,
                :workshop_supervisor?,
                :procurement?,            # was billing_officer?
                :finance_officer?,
                :current_user_role,
                :owner_color,
                :urgency_badge_class,
                :status_badge_class,
                :format_date,
                :can_access_pos?,
                :can_open_register?,
                :can_void_transactions?,
                :can_refund_transactions?,
                :is_ptsc?,
                :can_view_reports?,
                :can_close_register?,
                :invoice_status_badge_color,
                # Notification count helpers
                :unread_notifications_count,
                :pending_inspections_count,
                :pending_parts_count,
                :available_jobs_count,
                :qc_pending_count,
                :pending_quotations_count,
                :ready_for_pickup_count,
                :my_assigned_jobs_count,
                :alerts_count,
                :pending_parts_requests_count,
                :quotations_to_review_count,
                :pending_po_approval_count,
                # VMCOTT Namespaced Route Helpers - UPDATED
                :vmcott_security_gate_officer_dashboard_path,
                :vmcott_inspector_dashboard_path,
                :vmcott_inventory_manager_dashboard_path,
                :vmcott_mechanic_dashboard_path,
                :vmcott_workshop_supervisor_dashboard_path,
                :vmcott_procurement_dashboard_path,
                :vmcott_finance_dashboard_path,
                :vmcott_dashboard_path,
                # Navigation helper
                :skip_navigation?

  # =====================================================
  # Public Methods - UPDATED WITH NEW ROLE NAMES
  # =====================================================

  def current_agency
    @current_agency ||= current_user&.agency
  end

  def admin?
    return false unless current_user
    current_user.admin? || current_user.role == 'admin'
  end

  def manager?
    return false unless current_user
    current_user.manager? || current_user.role == 'manager' || admin?
  end

  def vmcott?
    current_agency&.code == 'VMCOTT'
  end
  alias_method :is_vmcott?, :vmcott?

  # New role check methods - UPDATED
  def security_gate_officer?
    current_user&.security_gate_officer? || false
  end

  def inspector?
    current_user&.inspector? || false
  end

  def inventory_manager?
    current_user&.inventory_manager? || false
  end

  def mechanic?
    current_user&.mechanic? || false
  end

  def workshop_supervisor?
    current_user&.maintenance_supervisor? || false
  end

  def procurement?
    current_user&.procurement? || false
  end

  def finance_officer?
    current_user&.finance? || false
  end

  # Keep old methods for backward compatibility during transition
  def receptionist?
    current_user&.receptionist? || false
  end

  def parts_coordinator?
    current_user&.parts_coordinator? || false
  end

  def billing_officer?
    current_user&.billing? || false
  end

  def is_ptsc?
    current_agency&.code == 'PTSC'
  end

  def current_user_role
    current_user&.role || 'guest'
  end

  # Notification count accessors (with defaults)
  def unread_notifications_count
    @unread_notifications_count || 0
  end

  def pending_inspections_count
    @pending_inspections_count || 0
  end

  def pending_parts_count
    @pending_parts_count || 0
  end

  def available_jobs_count
    @available_jobs_count || 0
  end

  def qc_pending_count
    @qc_pending_count || 0
  end

  def pending_quotations_count
    @pending_quotations_count || 0
  end

  def ready_for_pickup_count
    @ready_for_pickup_count || 0
  end

  def my_assigned_jobs_count
    @my_assigned_jobs_count || 0
  end

  def alerts_count
    @alerts_count || 0
  end

  def pending_parts_requests_count
    @pending_parts_requests_count || 0
  end

  def quotations_to_review_count
    @quotations_to_review_count || 0
  end

  def pending_po_approval_count
    @pending_po_approval_count || 0
  end

  # NEW: Helper method to determine if navigation should be hidden
  def skip_navigation?
    params[:controller] == 'screensaver' || 
    (params[:controller] == 'home' && params[:action] == 'index' && !user_signed_in?) ||
    params[:controller] == 'devise/sessions' ||
    params[:controller] == 'devise/passwords' ||
    params[:controller] == 'devise/registrations'
  end

  # POS permissions
  def can_access_pos?
    current_user&.can_access_pos? || false
  end

  def can_open_register?
    current_user&.can_open_register? || false
  end

  def can_close_register?
    current_user&.can_close_register? || false
  end

  def can_void_transactions?
    current_user&.can_void_transactions? || false
  end

  def can_refund_transactions?
    current_user&.can_refund_transactions? || false
  end

  def can_view_reports?
    current_user&.can_view_reports? || false
  end

  # Color coding for service owners
  def owner_color(owner)
    case owner.to_s.downcase
    when 'ptsc'         then 'primary'
    when 'police'       then 'danger'
    when 'fire service', 'fire' then 'warning'
    when 'ambulance', 'medical' then 'info'
    when 'government'   then 'secondary'
    else 'dark'
    end
  end

  # Badge class for maintenance urgency
  def urgency_badge_class(urgency)
    case urgency.to_s.downcase
    when 'emergency'  then 'bg-danger text-white'
    when 'scheduled'  then 'bg-warning text-dark'
    when 'routine'    then 'bg-primary text-white'
    else 'bg-secondary text-white'
    end
  end

  # Badge class for maintenance status
  def status_badge_class(status)
    case status.to_s.downcase
    when 'completed' then 'bg-success text-white'
    when 'pending'   then 'bg-warning text-dark'
    when 'cancelled' then 'bg-secondary text-white'
    else 'bg-info text-white'
    end
  end

  # Badge color for invoice status
  def invoice_status_badge_color(status)
    case status
    when 'paid' then 'success'
    when 'reviewed' then 'info'
    when 'pending' then 'warning'
    when 'disputed' then 'danger'
    else 'secondary'
    end
  end

  # Format date consistently
  def format_date(date, format = "%Y-%m-%d")
    return "—" if date.blank?

    d =
      if date.is_a?(String)
        Date.parse(date) rescue nil
      elsif date.respond_to?(:to_date)
        date.to_date
      else
        nil
      end

    return "—" if d.nil?

    d.strftime(format)
  end

  # =====================================================
  # Authorization Methods - UPDATED WITH NEW ROLE NAMES
  # =====================================================
  
  def require_vmcott_user
    return if current_user&.admin?
    redirect_to root_path, alert: "Access denied. VMCOTT users only." unless vmcott?
  end

  # Role-specific authorization methods - UPDATED
  def require_security_gate_officer
    unless security_gate_officer? || admin?
      redirect_to root_path, alert: "Access denied. Security Gate Officer access only."
    end
  end

  def require_inspector
    unless inspector? || admin?
      redirect_to root_path, alert: "Access denied. Inspector access only."
    end
  end

  def require_inventory_manager
    unless inventory_manager? || admin?
      redirect_to root_path, alert: "Access denied. Inventory Manager access only."
    end
  end

  def require_mechanic
    unless mechanic? || admin?
      redirect_to root_path, alert: "Access denied. Mechanic access only."
    end
  end

  def require_workshop_supervisor
    unless workshop_supervisor? || admin?
      redirect_to root_path, alert: "Access denied. Workshop Supervisor access only."
    end
  end

  def require_procurement
    unless procurement? || admin?
      redirect_to root_path, alert: "Access denied. Procurement access only."
    end
  end

  def require_finance_officer
    unless finance_officer? || admin?
      redirect_to root_path, alert: "Access denied. Finance Officer access only."
    end
  end

  # Keep old methods for backward compatibility
  def require_receptionist
    unless receptionist? || admin?
      redirect_to root_path, alert: "Access denied. Receptionist access only."
    end
  end

  def require_parts_coordinator
    unless parts_coordinator? || admin?
      redirect_to root_path, alert: "Access denied. Parts Coordinator access only."
    end
  end

  def require_billing_officer
    unless billing_officer? || admin?
      redirect_to root_path, alert: "Access denied. Billing Officer access only."
    end
  end
  
  # POS Authorization Methods
  def require_pos_access
    unless can_access_pos?
      redirect_to root_path, alert: 'You do not have permission to access the POS system'
    end
  end

  def authorize_pos_void!
    unless can_void_transactions?
      redirect_to root_path, alert: 'You do not have permission to void transactions'
    end
  end

  def authorize_pos_refund!
    unless can_refund_transactions?
      redirect_to root_path, alert: 'You do not have permission to refund transactions'
    end
  end

  def authorize_open_register!
    unless can_open_register?
      redirect_to root_path, alert: 'You do not have permission to open the cash register'
    end
  end

  def authorize_close_register!
    unless can_close_register?
      redirect_to root_path, alert: 'You do not have permission to close the cash register'
    end
  end

  def authorize_view_reports!
    unless can_view_reports?
      redirect_to root_path, alert: 'You do not have permission to view reports'
    end
  end

  def authorize_ptsc_pos!
    return if is_ptsc?
    redirect_to root_path, alert: 'PTSC POS features are only available to PTSC staff'
  end

  # =====================================================
  # Authorization Shortcuts
  # =====================================================
  
  def authorize_admin!
    return if admin?
    flash[:alert] = "You are not authorized to perform this action."
    redirect_back(fallback_location: root_path)
  end

  def authorize_manager!
    return if manager?
    flash[:alert] = "You are not authorized to perform this action."
    redirect_back(fallback_location: root_path)
  end

  def authorize_fleet_manager!
    return if current_user&.fleet_manager? || manager?
    flash[:alert] = "You must be a fleet manager to perform this action."
    redirect_back(fallback_location: root_path)
  end

  def authorize_maintenance_supervisor!
    return if current_user&.maintenance_supervisor? || manager?
    flash[:alert] = "You must be a maintenance supervisor to perform this action."
    redirect_back(fallback_location: root_path)
  end

  def authorize_finance!
    return if current_user&.finance? || manager?
    flash[:alert] = "You must have finance access to perform this action."
    redirect_back(fallback_location: root_path)
  end

  def authorize_owner!(resource)
    return if admin?
    return if resource.user_id == current_user.id
    return if resource.respond_to?(:created_by) && resource.created_by == current_user.id
    
    flash[:alert] = "You are not authorized to manage this resource."
    redirect_back(fallback_location: root_path)
  end

  def authorize_viewer!(resource)
    return if admin? || manager?
    
    if resource.respond_to?(:user_id) && resource.user_id != current_user.id
      flash[:alert] = "You are not authorized to view this resource."
      redirect_back(fallback_location: root_path)
    end
  end

  # =====================================================
  # Pagination
  # =====================================================
  def per_page
    params[:per_page] || 20
  end
  helper_method :per_page

  # =====================================================
  # JSON Response Helpers
  # =====================================================
  def render_json_success(data = {}, message = nil)
    render json: {
      success: true,
      message: message,
      data: data
    }
  end

  def render_json_error(message = "An error occurred", errors = {}, status: :unprocessable_entity)
    render json: {
      success: false,
      message: message,
      errors: errors
    }, status: status
  end

  # =====================================================
  # Private Methods
  # =====================================================
  private

  def skip_pos_transaction_callback?
    controller_path == 'vmcott/parts' && action_name == 'edit'
  end

  def set_current_context
    # Set Current attributes before yielding to the action
    Current.user = current_user
    Current.set_request(request)
    yield
  ensure
    # Clean up after the action completes
    Current.reset
  end

  def set_current_user
    Current.user = current_user
  end

  def set_current_request
    Current.set_request(request)
  end
  
  def set_pos_transaction_current_user
    if defined?(PosTransaction)
      PosTransaction.with_current_user(current_user) do
        yield
      end
    else
      yield
    end
  end

  def set_timezone
    if current_user && current_user.respond_to?(:time_zone)
      time_zone = current_user.time_zone.presence || "UTC"
    else
      time_zone = "UTC"
    end
    
    Time.zone = time_zone
  end

  def set_agency_theme
    return unless current_agency && current_agency.theme
    session[:agency_theme] = current_agency.theme
  end

  def check_for_turbo_frame
    @turbo_frame_request = request.headers["Turbo-Frame"].present?
  end
  
  def prevent_real_payments_in_dev
    if Rails.env.development? && params[:controller] == 'purchase_orders' && 
       ['process_payment', 'authorize_payment'].include?(params[:action])
      Rails.logger.info "MOCK PAYMENT: #{params.inspect}"
      @mock_result = { success: true, transaction_id: "MOCK-#{SecureRandom.hex(8)}" }
    end
  end

  def handle_record_not_found
    respond_to do |format|
      format.html { redirect_to root_path, alert: "Record not found." }
      format.json { render json: { error: "Record not found" }, status: :not_found }
    end
  end

  def handle_parameter_missing(exception)
    respond_to do |format|
      format.html { 
        redirect_back fallback_location: root_path, 
                     alert: "Missing parameter: #{exception.param}" 
      }
      format.json { 
        render json: { error: "Missing parameter: #{exception.param}" }, 
               status: :bad_request 
      }
    end
  end

  def permit_nested_attributes_for(model_class, attributes)
    params.require(model_class).permit(attributes)
  end
end