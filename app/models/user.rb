# app/models/user.rb
class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable

  belongs_to :agency
  validates :agency, presence: true
  
  # Add time_zone attribute with default
  attribute :time_zone, :string, default: "UTC"
  
  # Store available roles for validation if needed
  # Updated roles to include all agencies and VMCOTT
  ROLES = %w[
    admin 
    fleet_manager 
    maintenance_supervisor 
    finance 
    driver
    vmcott_staff
    ptsc_staff
    ttps_staff
    ttdf_staff
    fire_staff
    health_staff
    education_staff
    other_agency_staff
  ].freeze
  
  # Add a safe time_zone method
  def time_zone
    # Return the stored time_zone or default to UTC
    self[:time_zone].presence || "UTC"
  end
  
  # Role methods - simplified for your dashboard
  def role
    # First, check if you have a 'role' column
    return self[:role] if has_attribute?(:role) && self[:role].present?
    
    # Check user_roles association if it exists
    if defined?(UserRole) && respond_to?(:user_roles)
      user_roles.first&.role&.name || 'fleet_manager' # Default to fleet manager
    else
      'fleet_manager' # default
    end
  end
  
  def role_name
    role.titleize
  end
  
  # ========================
  # BASIC ROLE CHECKS
  # ========================
  def admin?
    role == 'admin' || role == 'super_admin' || is_system_admin? || false
  end
  
  def manager?
    role == 'manager' || admin? || false
  end
  
  def fleet_manager?
    role == 'fleet_manager' || manager? || admin?
  end
  
  def maintenance_supervisor?
    role == 'maintenance_supervisor' || role == 'maintenance' || fleet_manager?
  end
  
  def finance?
    role == 'finance' || role == 'accountant' || admin?
  end
  
  def driver?
    role == 'driver' || role == 'operator'
  end
  
  # ========================
  # AGENCY-SPECIFIC ROLE CHECKS
  # ========================
  def vmcott_staff?
    role == 'vmcott_staff' || agency&.central? || admin?
  end
  
  def ptsc_staff?
    role == 'ptsc_staff' || agency&.transport? || fleet_manager? || admin?
  end
  
  def ttps_staff?
    role == 'ttps_staff' || agency&.police? || fleet_manager? || admin?
  end
  
  def ttdf_staff?
    role == 'ttdf_staff' || (agency&.code == 'TTDF') || fleet_manager? || admin?
  end
  
  def fire_staff?
    role == 'fire_staff' || agency&.fire? || fleet_manager? || admin?
  end
  
  def health_staff?
    role == 'health_staff' || (agency&.code == 'HEALTH') || fleet_manager? || admin?
  end
  
  def education_staff?
    role == 'education_staff' || (agency&.code == 'EDUCATION') || fleet_manager? || admin?
  end
  
  def other_agency_staff?
    role == 'other_agency_staff' || (!vmcott_staff? && !ptsc_staff? && !ttps_staff? && 
            !ttdf_staff? && !fire_staff? && !health_staff? && !education_staff?)
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
  # NEW INVOICE PERMISSIONS (Added for new controller)
  # ========================
  def can_create_invoices?
    # Only VMCOTT staff create invoices (they are the service provider)
    vmcott_staff? || admin? || finance?
  end
  
  def can_edit_invoices?
    # Only VMCOTT and finance can edit invoices
    vmcott_staff? || admin? || finance?
  end
  
  def can_review_invoices?
    # All agency staff can review invoices for their agency
    ptsc_staff? || ttps_staff? || ttdf_staff? || fire_staff? ||
    health_staff? || education_staff? || other_agency_staff? || 
    fleet_manager? || finance? || admin?
  end
  
  def can_pay_invoices?
    # Only finance roles can mark invoices as paid
    finance? || admin?
  end
  
  def can_dispute_invoices?
    # Agency staff can dispute invoices
    ptsc_staff? || ttps_staff? || ttdf_staff? || fire_staff? ||
    health_staff? || education_staff? || other_agency_staff? || 
    fleet_manager? || admin?
  end
  
  def can_view_invoice_reports?
    finance? || fleet_manager? || admin?
  end
  
  def can_sync_quickbooks?
    # VMCOTT and finance can sync with QuickBooks
    vmcott_staff? || finance? || admin?
  end
  
  def can_access_invoices?
    # All logged-in users except drivers can access invoices
    !driver? && !role.blank?
  end
  
  # ========================
  # NEW QUOTATION PERMISSIONS (Added for quotations controller)
  # ========================
  def can_manage_quotations?
    finance? || admin? || fleet_manager? || vmcott_staff?
  end
  
  def can_view_quotations?
    finance? || admin? || fleet_manager? || maintenance_supervisor? || ptsc_staff? || ttps_staff? || ttdf_staff?
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
    agency&.name || agency_display_name || 'Unknown Agency'
  end
  
  def agency_code
    agency&.code || 'N/A'
  end
  
  def agency_display_name
    return nil unless agency
    
    # Map agency codes to full names
    case agency.code
    when 'VMCOTT'
      'Vehicle Maintenance Company of Trinidad and Tobago'
    when 'PTSC'
      'Public Transport Service Corporation'
    when 'TTPS'
      'Trinidad and Tobago Police Service'
    when 'TTDF'
      'Trinidad and Tobago Defence Force'
    when 'FIRE'
      'Trinidad and Tobago Fire Service'
    when 'HEALTH'
      'Ministry of Health'
    when 'EDUCATION'
      'Ministry of Education'
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
      # Drivers only see their assigned vehicles
      agency.vehicles.where(driver_id: id)
    else
      # Agency staff see all vehicles for their agency
      agency.vehicles
    end
  end
  
  def agency_invoices
    if admin? || finance? || fleet_manager?
      # Admin/Finance/Fleet managers can see all invoices
      Invoice.all
    elsif vmcott_staff?
      # VMCOTT can see all invoices they created
      Invoice.all
    elsif agency.present?
      # Agency staff only see their agency's invoices
      # Join with vehicles that belong to this agency
      Invoice.joins(:vehicle).where(vehicles: { service_owner: agency_code })
    else
      Invoice.none
    end
  end
  
  def agency_quotations
    if admin? || finance? || fleet_manager?
      # Admin/Finance/Fleet managers can see all quotations
      Quotation.all
    elsif vmcott_staff?
      # VMCOTT can see all quotations they created
      Quotation.all
    elsif agency.present?
      # Agency staff only see their agency's quotations
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
  
  def can_view_reports?
    fleet_manager? || finance? || admin?
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
    name.presence || email.split('@').first.titleize
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
  
  # Get all agencies this user can access
  def accessible_agencies
    if admin? || finance? || fleet_manager?
      # Can access all agencies
      Agency.all
    elsif agency.present?
      # Only their agency
      [agency]
    else
      []
    end
  end
  
  # Check if user can access a specific agency
  def can_access_agency?(agency_to_check)
    return true if admin? || finance? || fleet_manager?
    agency == agency_to_check
  end
  
  # ========================
  # VEHICLE SERVICE OWNER
  # ========================
  # Note: Your vehicles have agency_id, not service_owner string
  # So we'll use agency_id for filtering
  
  def agency_vehicles
    return Vehicle.none unless agency
    Vehicle.where(agency_id: agency.id)
  end
  
  def can_access_vehicle?(vehicle)
    return true if admin? || finance? || fleet_manager?
    return false unless agency && vehicle.agency_id
    
    if driver?
      # Drivers can only access vehicles assigned to them
      vehicle.agency_id == agency.id && vehicle.driver_id == id
    else
      # Other agency staff can access all vehicles in their agency
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
  
  # New quotation view helpers
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
  
  def show_quotation_send_button?
    can_send_quotations? && !driver?
  end

  def can_send_quotations?
    finance? || admin? || fleet_manager? || vmcott_staff?
  end
  
  # ========================
  # AGENCY TYPE CHECKERS
  # ========================
  def is_ptsc?
    agency_code == 'PTSC'
  end
  
  def is_ttps?
    agency_code == 'TTPS'
  end
  
  def is_ttdf?
    agency_code == 'TTDF'
  end
  
  def is_vmcott?
    agency_code == 'VMCOTT'
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
  # JSON/API SERIALIZATION
  # ========================
  def as_json(options = {})
    super(options.merge(
      methods: [
        :display_name,
        :agency_name,
        :agency_code,
        :role_name,
        :role_summary,
        :financial_permissions,
        :fleet_permissions
      ],
      only: [:id, :email, :name, :created_at]
    ))
  end
end