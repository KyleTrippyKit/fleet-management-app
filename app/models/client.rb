# app/models/client.rb
class Client < ApplicationRecord
  # Associations
  belongs_to :agency, optional: true
  has_many :vehicles, as: :owner, dependent: :nullify
  has_many :invoices, as: :client, dependent: :nullify
  has_many :quotations, as: :client, dependent: :nullify
  has_many :vehicle_condition_reports, as: :client, dependent: :nullify
  
  # Enums with integer values
  enum :client_type, {
    agency: 0,        # PTSC, TTPS, etc. - Agency clients
    corporate: 1,     # Business clients
    individual: 2     # Walk-in customers
  }
  
  enum :payment_terms, {
    cash: 0,
    net_15: 1,
    net_30: 2,
    net_60: 3,
    deposit_balance: 4
  }
  
  # Validations
  validates :name, presence: true
  validates :email, uniqueness: true, allow_blank: true, format: { with: URI::MailTo::EMAIL_REGEXP, allow_blank: true }
  validates :phone, presence: true, format: { with: /\A[0-9+\-\s]+\z/, message: "only allows numbers, spaces, +, and -" }
  validates :credit_limit, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  
  # Scopes
  scope :active, -> { where(is_active: true) }
  scope :by_client_type, ->(type) { where(client_type: client_types[type]) if type.present? }
  
  # Display methods
  def display_name
    if agency.present?
      "#{name} (#{agency.code})"
    else
      name
    end
  end
  
  def client_type_display
    case client_type
    when 'agency'
      "Agency Client"
    when 'corporate'
      "Corporate Client"
    when 'individual'
      "Individual Client"
    else
      "Unknown"
    end
  end
  
  def payment_terms_display
    case payment_terms
    when 'cash'
      "Cash on Pickup"
    when 'net_15'
      "Net 15 Days"
    when 'net_30'
      "Net 30 Days"
    when 'net_60'
      "Net 60 Days"
    when 'deposit_balance'
      "Deposit + Balance"
    else
      "Not Set"
    end
  end
  
  # Override setter to handle both string and integer inputs
  def client_type=(value)
    if value.is_a?(String) && value.match?(/^\d+$/)
      # If it's a numeric string like "2", convert to integer
      super(value.to_i)
    elsif value.is_a?(String)
      # If it's a string like "individual", let the enum handle it
      super(value)
    else
      super
    end
  end
  
  # Financial methods
  def outstanding_balance
    invoices.where(status: ['pending', 'overdue']).sum(:amount)
  end
  
  def aging_summary
    {
      current: invoices.current_aging.sum(:amount),
      thirty_days: invoices.days_30_aging.sum(:amount),
      sixty_days: invoices.days_60_aging.sum(:amount),
      ninety_plus: invoices.over_90_aging.sum(:amount)
    }
  end
  
  def total_spent
    invoices.where(status: 'paid').sum(:amount)
  end
  
  # Status methods
  def active?
    is_active
  end
  
  def can_use_credit?
    credit_limit.to_f > 0 && outstanding_balance < credit_limit.to_f
  end
  
  def credit_available
    return 0 unless credit_limit.to_f > 0
    credit_limit.to_f - outstanding_balance
  end
  
  # Vehicle methods
  def vehicle_count
    vehicles.count
  end
  
  def active_vehicles
    vehicles.where(status: 'active')
  end
  
  def vehicles_in_maintenance
    vehicles.where(status: 'maintenance')
  end
  
  # Condition report methods
  def recent_condition_reports(limit = 5)
    vehicle_condition_reports.completed.order(created_at: :desc).limit(limit)
  end
  
  def has_outstanding_reports?
    vehicle_condition_reports.where(status: 'draft').exists?
  end
  
  # Invoice methods
  def unpaid_invoices
    invoices.where(status: ['pending', 'overdue'])
  end
  
  def overdue_invoices
    invoices.overdue
  end
  
  # Search scope
  scope :search, ->(query) {
    return all if query.blank?
    where("name ILIKE :q OR email ILIKE :q OR phone ILIKE :q", q: "%#{query}%")
  }
  
  # To help with form selection
  def self.options_for_select
    active.order(:name).map { |c| [c.display_name, c.id] }
  end
  
  # For debugging - shows what values are accepted
  def self.valid_client_type_values
    client_types.keys.map(&:to_s)
  end
  
  def self.valid_payment_terms_values
    payment_terms.keys.map(&:to_s)
  end
end