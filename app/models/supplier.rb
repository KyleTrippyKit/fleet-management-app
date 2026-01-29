class Supplier < ApplicationRecord
  has_many :parts
  has_many :purchase_requests
  has_many :vendor_invoices
  has_many :purchase_orders
  has_many :invoices
  has_many :vendor_parts
  has_many :parts_through_vendor, through: :vendor_parts, source: :part
  
  validates :name, presence: true
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true
  
  # Add uniqueness validation as mentioned in issue 4
  validates :name, uniqueness: true
  
  # Scope for active suppliers
  scope :active, -> { where(is_active: true) }
  
  # Search scope - FIXED: Proper scope syntax
  scope :search, ->(query) {
    return all if query.blank?
    where("name ILIKE ? OR email ILIKE ? OR phone ILIKE ? OR contact_person ILIKE ?",
          "%#{query}%", "%#{query}%", "%#{query}%", "%#{query}%")
  }
  
  # Class method for search (for backward compatibility)
  def self.search_by_query(query = nil)
    return all if query.blank?
    where("name ILIKE ? OR email ILIKE ? OR phone ILIKE ? OR contact_person ILIKE ?",
          "%#{query}%", "%#{query}%", "%#{query}%", "%#{query}%")
  end
  
  # Calculate total outstanding amount
  def total_outstanding
    vendor_invoices.where(status: ['pending', 'reviewed']).sum(:amount)
  end
  
  # Calculate total paid amount
  def paid_amount
    vendor_invoices.where(status: 'paid').sum(:amount)
  end
  
  # Alternative paid_amount using scope if vendor_invoices has 'paid' scope
  def paid_amount_via_scope
    vendor_invoices.respond_to?(:paid) ? vendor_invoices.paid.sum(:amount) : vendor_invoices.where(status: 'paid').sum(:amount)
  end
  
  # Count open invoices
  def open_invoice_count
    vendor_invoices.where(status: ['pending', 'reviewed']).count
  end
  
  # Get overdue invoices
  def overdue_invoices
    vendor_invoices.where("due_date < ? AND status IN (?)", Date.current, ['pending', 'reviewed'])
  end
  
  # Calculate total overdue amount
  def overdue_amount
    overdue_invoices.sum(:amount)
  end
  
  # Get recent activity
  def recent_invoices(limit = 5)
    vendor_invoices.order(created_at: :desc).limit(limit)
  end
  
  # Get recent purchase orders
  def recent_purchase_orders(limit = 5)
    purchase_orders.order(created_at: :desc).limit(limit)
  end
  
  # Get inventory summary
  def inventory_summary
    {
      total_parts: parts.count,
      low_stock: parts.where("current_stock <= minimum_stock").count,
      out_of_stock: parts.where("current_stock <= 0").count,
      total_inventory_value: parts.sum("current_stock * cost_price")
    }
  end
  
  # Get performance metrics
  def performance_metrics
    {
      average_payment_days: calculate_average_payment_days,
      on_time_payment_rate: calculate_on_time_payment_rate,
      average_days_to_pay: average_days_to_pay,  # Added from issue 4
      total_transactions: vendor_invoices.count
    }
  end
  
  # Convert to card data for UI display
  def to_card_data
    {
      id: id,
      name: name,
      email: email,
      phone: phone,
      contact_person: contact_person,
      outstanding_amount: total_outstanding,
      paid_amount: paid_amount,
      open_invoices: open_invoice_count,
      overdue_invoices: overdue_invoices.count,
      overdue_amount: overdue_amount,
      is_active: is_active,
      last_invoice_date: vendor_invoices.maximum(:invoice_date),
      created_at: created_at
    }
  end
  
  # Get invoice statistics by status
  def invoice_statistics
    {
      pending: vendor_invoices.where(status: 'pending').sum(:amount),
      reviewed: vendor_invoices.where(status: 'reviewed').sum(:amount),
      paid: vendor_invoices.where(status: 'paid').sum(:amount),
      rejected: vendor_invoices.where(status: 'rejected').sum(:amount)
    }
  end
  
  # Get monthly spending
  def monthly_spending(year = Date.current.year)
    (1..12).map do |month|
      start_date = Date.new(year, month, 1)
      end_date = start_date.end_of_month
      amount = vendor_invoices
        .where(status: 'paid')
        .where(invoice_date: start_date..end_date)
        .sum(:amount)
      { month: month, amount: amount }
    end
  end
  
  # Calculate total spending with this supplier
  def total_spending
    vendor_invoices.where(status: 'paid').sum(:amount)
  end
  
  # String representation for forms and displays
  def to_s
    name
  end
  
  # Check if supplier has any pending payments
  def has_pending_payments?
    vendor_invoices.where(status: ['pending', 'reviewed']).exists?
  end
  
  # Check if supplier has overdue invoices
  def has_overdue_invoices?
    overdue_invoices.exists?
  end
  
  # Calculate supplier rating based on performance
  def performance_rating
    rating = 5.0
    
    # Deduct for overdue invoices
    if has_overdue_invoices?
      rating -= 1.0
    end
    
    # Adjust based on on-time payment rate
    on_time_rate = calculate_on_time_payment_rate
    if on_time_rate < 70
      rating -= 1.0
    elsif on_time_rate > 90
      rating += 0.5
    end
    
    # Ensure rating is between 1-5
    [[rating, 1.0].max, 5.0].min
  end
  
  # Get payment terms description
  def payment_terms_description
    case payment_terms
    when 'net30'
      'Net 30 days'
    when 'net15'
      'Net 15 days'
    when 'net45'
      'Net 45 days'
    when 'net60'
      'Net 60 days'
    when 'prepaid'
      'Prepaid'
    when 'cod'
      'Cash on Delivery'
    else
      payment_terms.presence || 'Net 30 days'
    end
  end
  
  # Get supplier activity level
  def activity_level
    invoice_count = vendor_invoices.count
    
    if invoice_count == 0
      'inactive'
    elsif invoice_count <= 5
      'low'
    elsif invoice_count <= 20
      'medium'
    else
      'high'
    end
  end
  
  # Average days to pay (from issue 4)
  def average_days_to_pay
    paid_invoices = vendor_invoices.where(status: 'paid').where.not(paid_date: nil).where.not(invoice_date: nil)
    return 0 if paid_invoices.empty?
    
    total_days = paid_invoices.sum do |invoice|
      payment_date = invoice.paid_date || invoice.updated_at.to_date
      invoice_date = invoice.invoice_date
      (payment_date - invoice_date).to_i
    end
    
    (total_days.to_f / paid_invoices.count).round(2)
  end
  
  # Get next expected payment amount
  def next_payment_amount
    next_due_invoice = vendor_invoices
      .where(status: ['pending', 'reviewed'])
      .where.not(due_date: nil)
      .order(due_date: :asc)
      .first
    
    next_due_invoice ? next_due_invoice.amount : 0
  end
  
  # Get next payment date
  def next_payment_date
    vendor_invoices
      .where(status: ['pending', 'reviewed'])
      .where.not(due_date: nil)
      .order(due_date: :asc)
      .first
      &.due_date
  end
  
  # Get payment history summary
  def payment_history_summary(months = 6)
    end_date = Date.current
    start_date = months.months.ago
    
    payments = vendor_invoices
      .where(status: 'paid')
      .where(paid_date: start_date..end_date)
      .order(paid_date: :desc)
    
    {
      total_payments: payments.count,
      total_amount: payments.sum(:amount),
      average_payment: payments.average(:amount).to_f.round(2),
      payments_by_month: payments.group_by_month(:paid_date).sum(:amount)
    }
  end
  
  private
  
  def calculate_average_payment_days
    paid_invoices = vendor_invoices.where(status: 'paid')
    return 0 if paid_invoices.empty?
    
    total_days = paid_invoices.sum do |invoice|
      payment_date = invoice.updated_at.to_date
      invoice_date = invoice.invoice_date
      (payment_date - invoice_date).to_i
    end
    
    total_days / paid_invoices.count
  end
  
  def calculate_on_time_payment_rate
    paid_invoices = vendor_invoices.where(status: 'paid')
    return 0 if paid_invoices.empty?
    
    on_time = paid_invoices.count do |invoice|
      payment_date = invoice.updated_at.to_date
      invoice.due_date.nil? || payment_date <= invoice.due_date
    end
    
    (on_time.to_f / paid_invoices.count * 100).round(2)
  end
  
  # Add method to ensure vendor_invoices has a 'paid' scope
  def ensure_paid_scope_availability
    # This is a helper method to check if VendorInvoice model has 'paid' scope
    # You should define this scope in your VendorInvoice model:
    # scope :paid, -> { where(status: 'paid') }
    VendorInvoice.respond_to?(:paid)
  end
end