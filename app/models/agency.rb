# app/models/agency.rb
class Agency < ApplicationRecord
  # Validations
  validates :code, presence: true, uniqueness: true
  validates :name, presence: true
  
  # Associations
  has_many :users, dependent: :destroy
  has_many :vehicles, dependent: :destroy
  has_many :drivers, dependent: :destroy
  has_many :alerts, dependent: :destroy
  has_many :routes, dependent: :destroy
  has_many :fare_rules, through: :routes
  has_many :cashier_sessions, dependent: :destroy
  has_many :pos_transactions, through: :cashier_sessions
  has_many :accounts, dependent: :destroy
  has_many :agency_settings, dependent: :destroy
  has_many :invoices, through: :vehicles
  has_many :maintenance_requests, foreign_key: :requesting_agency_id, dependent: :destroy
  has_many :processed_maintenance_requests, class_name: 'MaintenanceRequest', 
           foreign_key: :processing_agency_id, dependent: :destroy
  has_many :rfqs, foreign_key: :requesting_agency_id, dependent: :destroy
  has_many :processed_rfqs, class_name: 'Rfq', foreign_key: :processing_agency_id, dependent: :destroy
  has_many :quotations, through: :rfqs
  has_many :purchase_orders, through: :vehicles
  has_many :job_templates, dependent: :destroy
  has_many :parts, through: :job_templates
  has_many :access_logs, dependent: :destroy
  has_many :account_transactions, dependent: :destroy
  has_many :monthly_statements, dependent: :destroy
  has_many :payment_schedules, dependent: :destroy
  
  # Agency configuration hash for dynamic styling and information
  AGENCY_CONFIGURATIONS = {
    'VMCOTT' => {
      name: 'Vehicle Maintenance Company of Trinidad and Tobago',
      short_name: 'VMCOTT',
      address: 'Ministry of Works, Port of Spain',
      phone: '(868) 623-0001',
      procurement_email: 'procurement@vmcott.gov.tt',
      color_scheme: 'blue',
      icon: 'gear-wide',
      gradient_start: '#1a237e',
      gradient_end: '#283593',
      role: 'central',
      has_pos: false,
      can_process_quotations: true,
      can_create_job_templates: true
    },
    'PTSC' => {
      name: 'Public Transport Service Corporation',
      short_name: 'PTSC',
      address: 'PTS House, South Quay, Port of Spain',
      phone: '(868) 623-0002',
      procurement_email: 'procurement@ptsc.gov.tt',
      color_scheme: 'green',
      icon: 'bus-front',
      gradient_start: '#1b5e20',
      gradient_end: '#2e7d32',
      role: 'transport',
      has_pos: true,
      can_process_quotations: false,
      can_create_job_templates: false
    },
    'TTPS' => {
      name: 'Trinidad and Tobago Police Service',
      short_name: 'TTPS',
      address: 'Police Headquarters, St Vincent Street, Port of Spain',
      phone: '(868) 623-0003',
      procurement_email: 'procurement@ttps.gov.tt',
      color_scheme: 'blue',
      icon: 'shield',
      gradient_start: '#0d47a1',
      gradient_end: '#1565c0',
      role: 'security',
      has_pos: false,
      can_process_quotations: false,
      can_create_job_templates: false
    },
    'TTDF' => {
      name: 'Trinidad and Tobago Defence Force',
      short_name: 'TTDF',
      address: 'Fire Headquarters, Wrightson Road, Port of Spain',
      phone: '(868) 623-0004',
      procurement_email: 'procurement@ttdf.gov.tt',
      color_scheme: 'red',
      icon: 'shield-check',
      gradient_start: '#b71c1c',
      gradient_end: '#c62828',
      role: 'security',
      has_pos: false,
      can_process_quotations: false,
      can_create_job_templates: false
    },
    'FIRE' => {
      name: 'Trinidad and Tobago Fire Service',
      short_name: 'Fire Service',
      address: 'Fire Headquarters, Wrightson Road, Port of Spain',
      phone: '(868) 623-0005',
      procurement_email: 'procurement@fireservice.gov.tt',
      color_scheme: 'orange',
      icon: 'fire',
      gradient_start: '#e65100',
      gradient_end: '#ef6c00',
      role: 'emergency',
      has_pos: false,
      can_process_quotations: false,
      can_create_job_templates: false
    },
    'HEALTH' => {
      name: 'Ministry of Health',
      short_name: 'Health',
      address: 'Independence Square, Port of Spain',
      phone: '(868) 623-0006',
      procurement_email: 'procurement@health.gov.tt',
      color_scheme: 'teal',
      icon: 'heart-pulse',
      gradient_start: '#004d40',
      gradient_end: '#00695c',
      role: 'ministry',
      has_pos: false,
      can_process_quotations: false,
      can_create_job_templates: false
    },
    'EDUCATION' => {
      name: 'Ministry of Education',
      short_name: 'Education',
      address: 'Education Towers, St Vincent Street, Port of Spain',
      phone: '(868) 623-0007',
      procurement_email: 'procurement@education.gov.tt',
      color_scheme: 'purple',
      icon: 'book',
      gradient_start: '#4a148c',
      gradient_end: '#6a1b9a',
      role: 'ministry',
      has_pos: false,
      can_process_quotations: false,
      can_create_job_templates: false
    },
    'JOTT' => {
      name: 'Judiciary of Trinidad and Tobago',
      short_name: 'Judiciary',
      address: 'Hall of Justice, Knox Street, Port of Spain',
      phone: '(868) 623-0008',
      procurement_email: 'procurement@judiciary.gov.tt',
      color_scheme: 'purple',
      icon: 'scale',
      gradient_start: '#4a148c',
      gradient_end: '#6a1b9a',
      role: 'judiciary',
      has_pos: false,
      can_process_quotations: false,
      can_create_job_templates: false
    }
  }.freeze
  
  # Scopes
  scope :active, -> { where.not(code: nil) }
  scope :central, -> { where(code: 'VMCOTT') }
  scope :subordinate, -> { where.not(code: 'VMCOTT') }
  scope :transport, -> { where(code: ['PTSC']) }
  scope :security, -> { where(code: ['TTPS', 'TTDF']) }
  scope :emergency, -> { where(code: ['FIRE']) }
  scope :ministry, -> { where(code: ['HEALTH', 'EDUCATION']) }
  scope :with_pos, -> { where(code: ['PTSC']) }
  scope :can_process_quotations, -> { where(code: ['VMCOTT']) }
  scope :can_create_job_templates, -> { where(code: ['VMCOTT']) }
  
  # Class Methods
  def self.central_agency
    find_by(code: 'VMCOTT')
  end
  
  def self.subordinate_agencies
    where.not(code: 'VMCOTT')
  end
  
  def self.transport_agencies
    where(code: ['PTSC'])
  end
  
  def self.security_agencies
    where(code: ['TTPS', 'TTDF'])
  end
  
  def self.emergency_agencies
    where(code: ['FIRE'])
  end
  
  def self.ministry_agencies
    where(code: ['HEALTH', 'EDUCATION'])
  end
  
  def self.seed_all_agencies
    AGENCY_CONFIGURATIONS.each do |code, config|
      find_or_create_by!(code: code) do |agency|
        agency.name = config[:name]
        agency.theme = config[:color_scheme]
      end
    end
  end
  
  # Instance Methods - Type Checks
  def central?
    code == 'VMCOTT'
  end
  
  def transport?
    code == 'PTSC'
  end
  
  def police?
    code == 'TTPS'
  end
  
  def defence?
    code == 'TTDF'
  end
  
  def fire?
    code == 'FIRE'
  end
  
  def health?
    code == 'HEALTH'
  end
  
  def education?
    code == 'EDUCATION'
  end
  
  def judiciary?
    code == 'JOTT'
  end
  
  def ministry?
    health? || education?
  end
  
  # Instance Methods - Configuration
  def display_name
    AGENCY_CONFIGURATIONS[code]&.fetch(:name, nil) || name || code
  end
  
  def short_name
    AGENCY_CONFIGURATIONS[code]&.fetch(:short_name, nil) || code
  end
  
  def agency_config
    AGENCY_CONFIGURATIONS[code] || {}
  end
  
  def color_scheme
    agency_config[:color_scheme] || 'primary'
  end
  
  def icon
    agency_config[:icon] || 'building'
  end
  
  def gradient_colors
    {
      start: agency_config[:gradient_start] || '#0d6efd',
      end: agency_config[:gradient_end] || '#0d6efd'
    }
  end
  
  def has_pos_system?
    agency_config[:has_pos] || false
  end
  
  def can_process_quotations?
    agency_config[:can_process_quotations] || false
  end
  
  def can_create_job_templates?
    agency_config[:can_create_job_templates] || false
  end
  
  def role
    agency_config[:role] || 'subordinate'
  end
  
  # Helper method to get CSS class for agency
  def css_class
    "agency-#{color_scheme}"
  end
  
  # Helper method for badge color based on agency type
  def badge_color
    case role
    when 'central' then 'primary'
    when 'transport' then 'success'
    when 'security' then 'danger'
    when 'emergency' then 'warning'
    when 'ministry' then 'info'
    when 'judiciary' then 'dark'
    else 'secondary'
    end
  end
  
  # Analytics and Stats
  def total_vehicles
    vehicles.count
  end
  
  def active_vehicles
    vehicles.where(status: 'active').count
  end
  
  def total_drivers
    drivers.count
  end
  
  def active_drivers
    drivers.where(status: 'active').count
  end
  
  def maintenance_stats
    {
      total: vehicles.joins(:maintenances).count,
      pending: vehicles.joins(:maintenances).where(maintenances: { status: 'pending' }).count,
      completed: vehicles.joins(:maintenances).where(maintenances: { status: 'completed' }).count,
      scheduled: vehicles.joins(:maintenances).where(maintenances: { status: 'scheduled' }).count
    }
  end
  
  def purchase_order_stats
    {
      total: purchase_orders.count,
      draft: purchase_orders.where(status: 'draft').count,
      approved: purchase_orders.where(status: 'approved').count,
      ordered: purchase_orders.where(status: 'ordered').count,
      received: purchase_orders.where(status: 'received').count,
      paid: purchase_orders.where(status: 'paid').count
    }
  end
  
  def quotation_stats
    {
      total: quotations.count,
      pending: quotations.where(status: 0).count,
      accepted: quotations.where(status: 1).count,
      rejected: quotations.where(status: 2).count
    }
  end
  
  def job_template_stats
    {
      total: job_templates.count,
      active: job_templates.where(is_active: true).count,
      categories: job_templates.pluck(:category).uniq
    }
  end
  
  def pos_stats
    return {} unless has_pos_system?
    
    {
      total_sales: pos_transactions.sum(:amount),
      total_transactions: pos_transactions.count,
      recent_transactions: pos_transactions.order(created_at: :desc).limit(10)
    }
  end
  
  # Method to get all vehicles needing maintenance
  def vehicles_needing_maintenance
    vehicles.joins(:maintenances)
            .where(maintenances: { status: ['pending', 'scheduled'] })
            .distinct
  end
  
  # Method to get low stock parts
  def low_stock_parts
    Part.joins(:job_templates)
        .where(job_templates: { agency_id: id })
        .where('parts.current_stock <= parts.reorder_point')
        .distinct
  end
  
  # Method to get pending purchase orders
  def pending_purchase_orders
    purchase_orders.where(status: ['draft', 'pending_approval', 'approved'])
  end
  
  # Method to get active cashier sessions
  def active_cashier_sessions
    return [] unless has_pos_system?
    cashier_sessions.where(status: 0)  # Assuming 0 = active
  end
  
  # Override to_s for better display
  def to_s
    display_name
  end
  
  # For form select helpers
  def to_option
    [display_name, id]
  end
end