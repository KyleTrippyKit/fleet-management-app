# app/models/user.rb
# Replace the ENTIRE file with this (copy/paste).
#
# ✅ Fixes the dangerous "def role" override (removed)
# ✅ Keeps your existing permissions + helpers
# ✅ Makes role checks consistent + safe (uses self[:role])
# ✅ Fixes system_user selecting admins correctly
# ✅ Keeps your ROLES constants + compatibility .roles hash

class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable

  belongs_to :agency
  validates :agency, presence: true

  # Associations
  has_many :cashier_sessions
  has_many :quotations, foreign_key: :created_by_id
  has_many :created_purchase_orders, class_name: "PurchaseOrder", foreign_key: :created_by_id
  has_many :approved_purchase_orders, class_name: "PurchaseOrder", foreign_key: :approved_by_id

  # ========================
  # ROLE (Rails 8 safe, simple)
  # ========================
  # Rails 8 requires a different syntax
  attribute :role, :string, default: 'clerk'
  
  # Define role constants
  ROLE_CLERK = 'clerk'
  ROLE_SUPERVISOR = 'supervisor'
  ROLE_FINANCE = 'finance'
  ROLE_ADMIN = 'admin'
  ROLE_SCANNER = 'scanner'

  # Define valid roles
  ROLES = [ROLE_CLERK, ROLE_SUPERVISOR, ROLE_FINANCE, ROLE_ADMIN, ROLE_SCANNER].freeze
  
  # Role query methods
  def clerk?
    role == ROLE_CLERK
  end
  
  def supervisor?
    role == ROLE_SUPERVISOR || admin?
  end

  def finance?
    role == ROLE_FINANCE || admin?
  end

  def admin?
    role == ROLE_ADMIN || role == 'super_admin' || is_system_admin? || false
  end
  
  # For compatibility with old code that expects enum methods
  def self.roles
    {
      clerk: ROLE_CLERK,
      supervisor: ROLE_SUPERVISOR,
      finance: ROLE_FINANCE,
      admin: ROLE_ADMIN,
      fleet_manager: ROLE_FLEET_MANAGER,
      maintenance_supervisor: ROLE_MAINTENANCE_SUPERVISOR,
      maintenance: ROLE_MAINTENANCE,
      driver: ROLE_DRIVER,
      vmcott_staff: ROLE_VMCOTT_STAFF
    }
  end

  # ========================
  # TIME ZONE
  # ========================
  attribute :time_zone, :string, default: "UTC"

  def time_zone
    self[:time_zone].presence || "UTC"
  end

  # ========================
  # ROLE DISPLAY
  # ========================
  def role_name
    self[:role].to_s.titleize
  end

  # ========================
  # BASIC ROLE CHECKS
  # ========================
  def clerk?
    self[:role] == ROLE_CLERK
  end

  def supervisor?
    self[:role] == ROLE_SUPERVISOR || admin?
  end

  def finance?
    self[:role] == ROLE_FINANCE || admin?
  end

  def admin?
    self[:role] == ROLE_ADMIN || self[:role] == "super_admin" || is_system_admin? || false
  end

  def manager?
    self[:role] == "manager" || admin? || false
  end

  def scanner_role?
    self[:role] == ROLE_SCANNER
  end
  
  def fleet_manager?
    self[:role] == ROLE_FLEET_MANAGER || manager? || admin? || supervisor?
  end

  def maintenance_supervisor?
    self[:role] == ROLE_MAINTENANCE_SUPERVISOR ||
      self[:role] == ROLE_MAINTENANCE ||
      fleet_manager? || supervisor? || admin?
  end

  def driver?
    self[:role] == ROLE_DRIVER || self[:role] == "operator"
  end

  def vmcott_staff?
    self[:role] == ROLE_VMCOTT_STAFF || (agency&.central? && !admin?) || false
  end

  # ========================
  # INITIALS METHOD
  # ========================
  def initials
    base = name.presence || email.to_s
    parts = base.strip.split(/\s+/)

    # If a real name exists: "Justin Ramdin" => "JR"
    if name.present? && parts.length >= 2
      return (parts.first[0].to_s + parts.last[0].to_s).upcase
    end

    # If only one word name: "Justin" => "JU"
    if name.present? && parts.length == 1
      return parts.first[0, 2].to_s.upcase
    end

    # Fallback to email: "kyle@..." => "KY"
    user_part = email.to_s.split("@").first.to_s
    user_part[0, 2].to_s.upcase
  end

  # ========================
  # SYSTEM USER METHOD (Added for PaymentAudit)
  # ========================
  def self.system_user
    find_by(email: "system@example.com") ||
      where(role: ROLE_ADMIN).first ||
      where.not(role: ROLE_DRIVER).first ||
      first ||
      new(name: "System", email: "system@example.com", role: ROLE_ADMIN)
  end

  # ========================
  # AGENCY-SPECIFIC ROLE CHECKS
  # ========================
  def ptsc_staff?
    agency&.transport? || fleet_manager? || admin?
  end

  def ttps_staff?
    agency&.police? || fleet_manager? || admin?
  end

  def ttdf_staff?
    (agency&.code == "TTDF") || fleet_manager? || admin?
  end

  def fire_staff?
    agency&.fire? || fleet_manager? || admin?
  end

  def health_staff?
    (agency&.code == "HEALTH") || fleet_manager? || admin?
  end

  def education_staff?
    (agency&.code == "EDUCATION") || fleet_manager? || admin?
  end

  def other_agency_staff?
    !vmcott_staff? && !ptsc_staff? && !ttps_staff? &&
      !ttdf_staff? && !fire_staff? && !health_staff? && !education_staff?
  end

  # Legacy compatibility methods
  def vmcott?
    vmcott_staff?
  end

  def ptsc?
    ptsc_staff?
  end

  def ttps?
    ttps_staff?
  end

  def ttdf?
    ttdf_staff?
  end

  def fire?
    fire_staff?
  end

  # ========================
  # POS PERMISSIONS
  # ========================
  def can_access_pos?
    clerk? || supervisor? || finance? || admin? || fleet_manager? || ptsc_staff?
  end

  def can_open_register?
    clerk? || finance? || admin? || supervisor? || fleet_manager?
  end

  def can_close_register?
    clerk? || finance? || admin? || supervisor? || fleet_manager?
  end

  def can_void_transactions?
    supervisor? || finance? || admin? || fleet_manager?
  end

  def can_refund_transactions?
    supervisor? || finance? || admin? || fleet_manager?
  end

  def can_view_reports?
    finance? || supervisor? || admin? || fleet_manager?
  end

  def can_manage_quickbooks?
    finance? || admin?
  end

  def can_manage_invoices?
    finance? || admin?
  end

  # Enhanced POS permissions with role-based fallback
  def can_void_pos?
    return true if can_void_transactions?

    if defined?(RolePermission) && respond_to?(:role_permissions)
      role_permissions.any? { |rp| rp.permission.key == "pos_void" }
    else
      can_void_transactions?
    end
  end

  def can_refund_pos?
    return true if can_refund_transactions?

    if defined?(RolePermission) && respond_to?(:role_permissions)
      role_permissions.any? { |rp| rp.permission.key == "pos_refund" }
    else
      can_refund_transactions?
    end
  end

  def can_view_pos_reports?
    return true if can_view_reports?

    if defined?(RolePermission) && respond_to?(:role_permissions)
      role_permissions.any? { |rp| rp.permission.key == "pos_reports" }
    else
      can_view_reports?
    end
  end

  # ========================
  # NEW INVOICE PERMISSIONS (Added for new controller)
  # ========================
  def can_create_invoices?
    vmcott_staff? || admin? || finance?
  end

  def can_edit_invoices?
    vmcott_staff? || admin? || finance?
  end

  def can_review_invoices?
    ptsc_staff? || ttps_staff? || ttdf_staff? || fire_staff? ||
      health_staff? || education_staff? || other_agency_staff? ||
      fleet_manager? || finance? || admin?
  end

  def can_pay_invoices?
    finance? || admin?
  end

  def can_dispute_invoices?
    ptsc_staff? || ttps_staff? || ttdf_staff? || fire_staff? ||
      health_staff? || education_staff? || other_agency_staff? ||
      fleet_manager? || admin?
  end

  def can_view_invoice_reports?
    finance? || fleet_manager? || admin?
  end

  def can_sync_quickbooks?
    vmcott_staff? || finance? || admin?
  end

  def can_access_invoices?
    !driver? && self[:role].present?
  end

  # ========================
  # NEW QUOTATION PERMISSIONS (Added for quotations controller)
  # ========================
  def can_manage_quotations?
    finance? || admin? || fleet_manager? || vmcott_staff?
  end

  def can_view_quotations?
    finance? || admin? || fleet_manager? || maintenance_supervisor? ||
      ptsc_staff? || ttps_staff? || ttdf_staff?
  end

  def can_create_quotations?
    finance? || admin? || fleet_manager? || vmcott_staff?
  end

  def can_edit_quotations?
    finance? || admin? || fleet_manager? || vmcott_staff?
  end

  def can_delete_quotations?
    admin? || finance?
  end

  def can_accept_quotations?
    finance? || admin?
  end

  def can_reject_quotations?
    finance? || admin? || fleet_manager?
  end

  def can_convert_quotations_to_po?
    finance? || admin?
  end

  def can_export_quotations?
    finance? || admin? || fleet_manager?
  end

  def can_view_quotation_reports?
    finance? || admin? || fleet_manager?
  end

  def can_send_quotations?
    finance? || admin? || fleet_manager? || vmcott_staff?
  end

  # ========================
  # AGENCY INFORMATION
  # ========================
  def agency_name
    agency&.name || agency_display_name || "Unknown Agency"
  end

  def agency_code
    agency&.code || "N/A"
  end

  def agency_display_name
    return nil unless agency

    case agency.code
    when "VMCOTT"
      "Vehicle Maintenance Company of Trinidad and Tobago"
    when "PTSC"
      "Public Transport Service Corporation"
    when "TTPS"
      "Trinidad and Tobago Police Service"
    when "TTDF"
      "Trinidad and Tobago Defence Force"
    when "FIRE"
      "Trinidad and Tobago Fire Service"
    when "HEALTH"
      "Ministry of Health"
    when "EDUCATION"
      "Ministry of Education"
    else
      agency.name
    end
  end

  # ========================
  # DATA SCOPE PERMISSIONS
  # ========================
  def scoped_vehicles
    return Vehicle.none unless agency.present?

    if driver?
      agency.vehicles.where(driver_id: id)
    else
      agency.vehicles
    end
  end

  def agency_invoices
    if admin? || finance? || fleet_manager?
      Invoice.all
    elsif vmcott_staff?
      Invoice.all
    elsif agency.present?
      # Prefer service_owner (code) if present; fall back to agency_id ownership
      Invoice.joins(:vehicle).where(
        "vehicles.service_owner = :code OR (vehicles.service_owner IS NULL OR vehicles.service_owner = '') AND vehicles.agency_id = :agency_id",
        code: agency_code,
        agency_id: agency.id
      )
    else
      Invoice.none
    end
  end

  def agency_quotations
    if admin? || finance? || fleet_manager?
      Quotation.all
    elsif vmcott_staff?
      Quotation.all
    elsif agency.present?
      Quotation.joins(:vehicle).where(vehicles: { agency_id: agency.id })
    else
      Quotation.none
    end
  end

  # ========================
  # DASHBOARD PERMISSIONS
  # ========================
  def can_see_financial_data?
    finance? || fleet_manager? || admin?
  end

  def can_see_maintenance_data?
    maintenance_supervisor? || fleet_manager? || admin?
  end

  def can_see_live_locations?
    fleet_manager? || driver? || admin?
  end

  def can_see_analytics?
    fleet_manager? || admin?
  end

  def can_manage_drivers?
    fleet_manager? || admin?
  end

  def can_add_vehicles?
    fleet_manager? || admin?
  end

  def can_edit_vehicles?
    fleet_manager? || admin?
  end

  def can_schedule_maintenance?
    maintenance_supervisor? || fleet_manager? || admin?
  end

  # Check if user has is_system_admin attribute
  def is_system_admin?
    has_attribute?(:is_system_admin) ? self[:is_system_admin] : false
  end

  # Display name for UI
  def display_name
    name.presence || email.split("@").first.titleize
  end

  # ========================
  # CONVENIENCE METHODS
  # ========================
  def is_agency_staff?
    !vmcott_staff? && !admin? && !finance? && !maintenance_supervisor?
  end

  def is_service_provider?
    vmcott_staff?
  end

  def is_subordinate_agency?
    agency && !agency.central?
  end

  def accessible_agencies
    if admin? || finance? || fleet_manager?
      Agency.all
    elsif agency.present?
      [agency]
    else
      []
    end
  end

  def can_access_agency?(agency_to_check)
    return true if admin? || finance? || fleet_manager?
    agency == agency_to_check
  end

  # ========================
  # VEHICLE ACCESS
  # ========================
  def agency_vehicles
    return Vehicle.none unless agency
    Vehicle.where(agency_id: agency.id)
  end

  def can_access_vehicle?(vehicle)
    return true if admin? || finance? || fleet_manager?
    return false unless agency && vehicle.agency_id

    if driver?
      vehicle.agency_id == agency.id && vehicle.driver_id == id
    else
      vehicle.agency_id == agency.id
    end
  end

  # ========================
  # QUICK CHECKS FOR VIEWS
  # ========================
  def show_invoice_create_button?
    can_create_invoices? && !driver?
  end

  def show_invoice_review_button?
    can_review_invoices? && !driver?
  end

  def show_invoice_pay_button?
    can_pay_invoices? && !driver?
  end

  def show_invoice_reports_button?
    can_view_invoice_reports? && !driver?
  end

  def show_financial_tab?
    can_see_financial_data? && !driver?
  end

  def show_analytics_tab?
    can_see_analytics? && !driver?
  end

  def show_maintenance_tab?
    can_see_maintenance_data? && !driver?
  end

  def show_quickbooks_sync_button?
    can_sync_quickbooks? && !driver?
  end

  def show_quotation_create_button?
    can_create_quotations? && !driver?
  end

  def show_quotation_edit_button?
    can_edit_quotations? && !driver?
  end

  def show_quotation_accept_button?
    can_accept_quotations? && !driver?
  end

  def show_quotation_reject_button?
    can_reject_quotations? && !driver?
  end

  def show_quotation_convert_button?
    can_convert_quotations_to_po? && !driver?
  end

  def show_quotation_export_button?
    can_export_quotations? && !driver?
  end

  def show_quotation_reports_button?
    can_view_quotation_reports? && !driver?
  end

  def show_pos_access_button?
    can_access_pos? && !driver?
  end

  def show_pos_void_button?
    can_void_transactions? && !driver?
  end

  def show_pos_refund_button?
    can_refund_transactions? && !driver?
  end

  def show_pos_reports_button?
    can_view_reports? && !driver?
  end

  # ========================
  # AGENCY TYPE CHECKERS
  # ========================
  def is_ptsc?
    agency_code == "PTSC"
  end

  def is_ttps?
    agency_code == "TTPS"
  end

  def is_ttdf?
    agency_code == "TTDF"
  end

  def is_vmcott?
    agency_code == "VMCOTT"
  end

  # ========================
  # PERMISSION GROUPS
  # ========================
  def financial_permissions
    {
      can_view_invoices: can_access_invoices?,
      can_create_invoices: can_create_invoices?,
      can_pay_invoices: can_pay_invoices?,
      can_view_quotations: can_view_quotations?,
      can_create_quotations: can_create_quotations?,
      can_accept_quotations: can_accept_quotations?,
      can_view_reports: can_view_reports?,
      can_sync_quickbooks: can_sync_quickbooks?
    }
  end

  def fleet_permissions
    {
      can_manage_vehicles: can_edit_vehicles?,
      can_manage_drivers: can_manage_drivers?,
      can_schedule_maintenance: can_schedule_maintenance?,
      can_view_analytics: can_see_analytics?,
      can_view_locations: can_see_live_locations?,
      can_manage_quotations: can_manage_quotations?
    }
  end

  def pos_permissions
    {
      can_access_pos: can_access_pos?,
      can_open_register: can_open_register?,
      can_close_register: can_close_register?,
      can_void_transactions: can_void_transactions?,
      can_refund_transactions: can_refund_transactions?,
      can_view_reports: can_view_reports?,
      can_manage_quickbooks: can_manage_quickbooks?,
      can_manage_invoices: can_manage_invoices?
    }
  end

  # ========================
  # ROLE SUMMARY FOR DISPLAY
  # ========================
  def role_summary
    if admin?
      "System Administrator - Full access to all features"
    elsif finance?
      "Finance Manager - Invoices, payments, quotations, and reports"
    elsif fleet_manager?
      "Fleet Manager - Vehicles, maintenance, drivers, and quotations"
    elsif maintenance_supervisor?
      "Maintenance Supervisor - Vehicle maintenance and scheduling"
    elsif vmcott_staff?
      "VMCOTT Staff - Service provider with quotation and invoice creation"
    elsif ptsc_staff? || ttps_staff? || ttdf_staff? || fire_staff? || health_staff? || education_staff?
      "#{agency_display_name} Staff - Agency vehicle management and invoice review"
    elsif driver?
      "Driver - Assigned vehicle access only"
    else
      "User - Limited access"
    end
  end

  # ========================
  # CASHIER SESSION METHODS
  # ========================
  def active_cashier_session
    cashier_sessions.open.order(opened_at: :desc).first
  end

  def active_cashier_session?
    active_cashier_session.present?
  end

  # PTSC-specific POS methods
  def can_process_ptsc_transactions?
    ptsc_staff? || finance? || admin? || fleet_manager?
  end

  def can_manage_fare_rules?
    fleet_manager? || finance? || admin? || ptsc_staff?
  end

  def can_view_route_reports?
    ptsc_staff? || fleet_manager? || finance? || admin?
  end

  # Current user context for callbacks
  def self.current
    Thread.current[:current_user] || Current.user
  end

  def self.current=(user)
    Thread.current[:current_user] = user
  end

  # PTSC-specific permissions for views
  def show_ptsc_pos_button?
    ptsc_staff? && can_access_pos?
  end

  def show_cashier_session_button?
    can_open_register? || active_cashier_session?
  end

  # Audit trail methods
  def create_audit_log(action, resource, details = {})
    return unless defined?(AuditLog)

    AuditLog.create(
      user: self,
      action: action.to_s,
      resource: resource,
      details: details,
      ip_address: Current.ip_address,
      user_agent: Current.user_agent
    )
  end

  # ========================
  # JSON/API SERIALIZATION
  # ========================
  def as_json(options = {})
    super(
      options.merge(
        methods: [
          :display_name,
          :agency_name,
          :agency_code,
          :role_name,
          :role_summary,
          :financial_permissions,
          :fleet_permissions,
          :pos_permissions
        ],
        only: [:id, :email, :name, :created_at]
      )
    )
  end
end
