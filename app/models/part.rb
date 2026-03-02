# app/models/part.rb
class Part < ApplicationRecord
  belongs_to :supplier, optional: true

  has_many :purchases
  has_many :maintenance_parts
  has_many :maintenances, through: :maintenance_parts
  has_many :purchase_order_items
  has_many :job_template_parts
  has_many :job_templates, through: :job_template_parts
  has_many :quotation_job_parts

  has_many :inventory_transactions, as: :inventory_item

  has_many :purchase_requests

  has_many :vendor_parts
  has_many :suppliers, through: :vendor_parts

  has_many :vendor_invoice_items

  # Validations
  validates :name, presence: true
  validates :part_number, uniqueness: true, allow_nil: true

  validates :current_stock, numericality: { greater_than_or_equal_to: 0 }
  validates :minimum_stock, numericality: { greater_than_or_equal_to: 0 }
  validates :reorder_point, numericality: { greater_than_or_equal_to: 0 }

  validates :cost_price, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :standard_markup_percentage, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true

  # Scopes
  scope :active, -> { where(is_active: true) }
  scope :consumable, -> { where(is_consumable: true) }
  scope :by_category, ->(category) { where(category: category) }
  scope :below_reorder_point, -> { where("current_stock <= reorder_point") }
  scope :out_of_stock, -> { where(current_stock: 0) }
  scope :low_stock, -> { below_reorder_point }
  scope :needs_reorder, -> { where("current_stock <= minimum_stock") }

  scope :search_by_name_or_number, ->(query) {
    where("name ILIKE ? OR part_number ILIKE ?", "%#{query}%", "%#{query}%")
  }

  default_scope -> { order(name: :asc) }

  # Display helpers
  def name_with_number
    part_number.present? ? "#{name} (#{part_number})" : name
  end

  def display_name
    name_with_number
  end

  # FIXED: Add name_with_details method for dropdowns
  def name_with_details
    stock_info = current_stock.to_i > 0 ? "Stock: #{current_stock}" : "Out of Stock"
    if part_number.present?
      "#{name} - #{part_number} (#{stock_info})"
    else
      "#{name} (#{stock_info})"
    end
  end

  # Pricing
  def selling_price
    return nil if cost_price.nil?
    markup = standard_markup_percentage || 30.0
    (cost_price * (1 + (markup / 100.0))).round(2)
  end

  alias_method :current_price, :selling_price

  def profit_margin
    return 0 if cost_price.nil? || cost_price <= 0 || selling_price.nil?
    ((selling_price - cost_price) / cost_price * 100).round(2)
  end

  def profit_amount
    return 0 if cost_price.nil? || selling_price.nil?
    selling_price - cost_price
  end

  # Defaults (safe)
  def reorder_point
    read_attribute(:reorder_point) || 10
  end

  def minimum_stock
    read_attribute(:minimum_stock) || 5
  end

  # Reorder + stock status
  def suggested_reorder_quantity
    target = reorder_point * 1.2
    [target - current_stock, minimum_stock * 2].max.ceil
  end

  def stock_status
    if current_stock.to_i.zero?
      "out_of_stock"
    elsif current_stock.to_i <= reorder_point.to_i
      "low_stock"
    else
      "in_stock"
    end
  end

  def stock_status_color
    case stock_status
    when "out_of_stock" then "danger"
    when "low_stock" then "warning"
    else "success"
    end
  end

  def needs_reorder?
    current_stock.to_i <= reorder_point.to_i
  end

  def can_fulfill?(quantity_needed)
    current_stock.to_i >= quantity_needed.to_i
  end

  def quantity_available
    current_stock
  end

  def quantity_needed_to_reorder
    minimum_stock.to_i - current_stock.to_i
  end

  def shortfall_for(needed_quantity)
    needed_quantity.to_i - current_stock.to_i
  end

  # -----------------------------
  # Inventory (final consistent model)
  # - stock_in / stock_out quantities stored POSITIVE
  # - adjustment can be +/- (direct delta)
  # - transaction_type determines direction
  # - current_stock is cached DB column updated in InventoryTransaction callbacks
  # -----------------------------
  def update_stock(quantity, transaction_type: "adjustment", user: nil, agency: nil, reference: nil, notes: nil, unit_price: nil)
    effective_agency = agency || user&.agency || Agency.first

    inventory_transactions.create!(
      quantity: quantity,
      transaction_type: transaction_type,
      user: user,
      agency: effective_agency,
      reference: reference,
      notes: notes,
      unit_price: unit_price || cost_price
    )
  end

  def stock_in(quantity, user: nil, agency: nil, reference: nil, notes: nil, unit_price: nil)
    update_stock(
      quantity.to_f.abs,
      transaction_type: "stock_in",
      user: user,
      agency: agency,
      reference: reference,
      notes: notes,
      unit_price: unit_price
    )
  end

  def stock_out(quantity, user: nil, agency: nil, reference: nil, notes: nil, unit_price: nil)
    update_stock(
      quantity.to_f.abs, # ✅ keep positive
      transaction_type: "stock_out",
      user: user,
      agency: agency,
      reference: reference,
      notes: notes,
      unit_price: unit_price
    )
  end

  # Audit truth from transactions
  def calculated_stock
    inventory_transactions.sum(<<~SQL.squish)
      CASE
        WHEN transaction_type IN ('receipt','release','stock_in','return','purchase')
          THEN ABS(quantity)
        WHEN transaction_type IN ('consumption','reservation','stock_out','damage','write_off','sale','transfer')
          THEN -ABS(quantity)
        WHEN transaction_type = 'adjustment'
          THEN quantity
        ELSE 0
      END
    SQL
  end

  # Repair cached current_stock from calculated_stock
  def recalculate_stock_from_transactions
    new_stock = calculated_stock.to_i
    update_column(:current_stock, new_stock) if new_stock != read_attribute(:current_stock).to_i
  end

  # Backward compatible method
  def adjust_stock(quantity, direction = :add, notes = nil, reference = nil)
    case direction
    when :add, :increase
      stock_in(quantity, notes: notes, reference: reference)
    when :subtract, :decrease, :use
      stock_out(quantity, notes: notes, reference: reference)
    else
      return false
    end
    true
  end

  # Reserve / release
  def reserve_stock(quantity, reference, notes = nil)
    return false unless can_fulfill?(quantity)

    inventory_transactions.create!(
      inventory_item: self,
      quantity: quantity.to_f.abs,
      transaction_type: :reservation,
      reference: reference,
      notes: notes || "Reserved for #{reference.class.name} #{reference.id}"
    )

    true
  end

  def release_stock(quantity, reference, notes = nil)
    reservations = inventory_transactions.reservation.where(reference: reference).sum(:quantity).to_f

    if reservations >= quantity.to_f
      inventory_transactions.create!(
        inventory_item: self,
        quantity: quantity.to_f.abs,
        transaction_type: :release,
        reference: reference,
        notes: notes || "Released from #{reference.class.name} #{reference.id}"
      )
      true
    else
      false
    end
  end

  # Consume parts for a job - UPDATED METHOD
  def consume_for_job(quantity, job, notes = nil)
    # Only deduct when job is completed, not when requested
    if job.completed?
      stock_out(quantity, 
        reference: job, 
        notes: notes || "Consumed for job #{job.id}"
      )
    end
  end

  # Receive stock from purchase order
  def receive_from_purchase(quantity, purchase_order, notes = nil)
    stock_in(quantity, 
      reference: purchase_order, 
      notes: notes || "Received from PO #{purchase_order.po_number}"
    )
  end

  # History + reporting
  def stock_history(days: 30)
    inventory_transactions
      .where("created_at >= ?", days.days.ago)
      .order(created_at: :desc)
  end

  def stock_movements(start_date: 30.days.ago, end_date: Time.current)
    inventory_transactions
      .where(created_at: start_date.beginning_of_day..end_date.end_of_day)
      .order(created_at: :desc)
  end

  def average_monthly_consumption
    consumption = inventory_transactions
      .where(transaction_type: ["consumption", "stock_out", "sale", "write_off", "damage"])
      .where("created_at >= ?", 90.days.ago)
      .sum(:quantity)
      .to_f

    consumption / 3.0
  end

  # Alternative consumption calculation
  def average_monthly_consumption_alt(months: 6)
    end_date = Time.current
    start_date = months.months.ago
    
    total_consumed = inventory_transactions.where(
      transaction_type: ['consumption', 'stock_out', 'damage', 'write_off', 'sale']
    )
      .where(created_at: start_date..end_date)
      .sum(:quantity)
    
    months_elapsed = [(Time.current - start_date) / 1.month, 1].max
    
    (total_consumed.to_f / months_elapsed).round(2)
  end

  def days_of_supply
    avg = average_monthly_consumption
    return Float::INFINITY if avg.zero?
    (current_stock.to_f / avg * 30).round
  end

  # Alternative days of supply
  def days_of_supply_alt
    avg_daily = average_monthly_consumption_alt / 30.0
    return Float::INFINITY if avg_daily <= 0
    (current_stock.to_f / avg_daily).round(1)
  end

  def stock_value
    current_stock.to_f * (cost_price || 0)
  end

  def profit_margin_data
    {
      cost_price: cost_price || 0,
      selling_price: selling_price || 0,
      profit_margin: profit_margin,
      profit_amount: profit_amount
    }
  end

  # Create purchase request
  def create_purchase_request(quantity = nil, urgency: 'normal', requested_by: nil, notes: nil)
    puts "PART MODEL: create_purchase_request called"
    puts "  Part ID: #{id}"
    puts "  Quantity: #{quantity}"
    puts "  Urgency: #{urgency}"
    puts "  Requested by ID: #{requested_by&.id}"
    
    quantity ||= suggested_reorder_quantity
    puts "  Final quantity: #{quantity}"
    
    pr = PurchaseRequest.new(
      part: self,
      quantity: quantity,
      urgency: urgency,
      requested_by: requested_by,
      notes: notes || "Auto-generated for low stock. Current: #{current_stock}, Min: #{minimum_stock}"
    )
    
    puts "  Purchase Request Valid?: #{pr.valid?}"
    puts "  Purchase Request Errors: #{pr.errors.full_messages}" unless pr.valid?
    
    if pr.save
      puts "  Purchase Request Saved! ID: #{pr.id}"
    else
      puts "  Failed to save: #{pr.errors.full_messages}"
    end
    
    pr
  end

  # Bulk update helper
  def self.bulk_stock_update(updates)
    results = { success: [], errors: [] }

    updates.each do |update|
      part = find_by(id: update[:part_id])

      if part.nil?
        results[:errors] << { part_id: update[:part_id], error: "Part not found" }
        next
      end

      begin
        if update[:quantity].to_f.positive?
          part.stock_in(update[:quantity], user: update[:user], agency: update[:agency], notes: update[:notes])
        elsif update[:quantity].to_f.negative?
          part.stock_out(update[:quantity].to_f.abs, user: update[:user], agency: update[:agency], notes: update[:notes])
        end

        results[:success] << { part_id: part.id, name: part.name, quantity: update[:quantity] }
      rescue => e
        results[:errors] << { part_id: part.id, name: part.name, error: e.message }
      end
    end

    results
  end

  # Vendor invoice receive
  def update_from_vendor_invoice(quantity, unit_price, invoice)
    transaction do
      update!(cost_price: unit_price)

      stock_in(
        quantity,
        user: invoice.user,
        agency: invoice.supplier&.agency,
        reference: invoice,
        notes: "Received via vendor invoice #{invoice.invoice_number}",
        unit_price: unit_price
      )
    end
  end

  # Profit helpers
  def calculate_profit_for_quantity(quantity)
    return 0 if cost_price.nil? || selling_price.nil?
    (selling_price - cost_price) * quantity.to_f
  end

  def markup_amount
    return 0 if cost_price.nil? || selling_price.nil?
    selling_price - cost_price
  end

  def markup_percentage
    return 0 if cost_price.nil? || cost_price <= 0 || selling_price.nil?
    ((selling_price - cost_price) / cost_price * 100).round(2)
  end

  # Convenience methods
  def increment_stock(amount, **options)
    stock_in(amount, **options)
  end

  def decrement_stock(amount, **options)
    stock_out(amount, **options)
  end

  # Upcoming demand
  def upcoming_demand
    # Sum of all quantities needed in pending quotations
    QuotationJobPart.joins(quotation_job: :quotation)
      .where(part_id: id)
      .where(quotations: { status: ['draft', 'sent', 'pending_acceptance'] })
      .sum(:quantity)
  end

  # Alternative reorder quantity
  def suggested_reorder_quantity_alt
    avg_consumption = average_monthly_consumption_alt
    lead_time_needed = (avg_consumption * (lead_time_days || 7) / 30.0).ceil
    safety_stock = (avg_consumption * 0.5).ceil # 2 weeks safety stock
    
    needed = minimum_stock - current_stock + lead_time_needed + safety_stock
    [needed, 0].max
  end

  # Stock snapshot for reporting
  def stock_snapshot
    {
      id: id,
      name: name,
      part_number: part_number,
      current_stock: current_stock,
      minimum_stock: minimum_stock,
      reorder_point: reorder_point,
      cost_price: cost_price,
      selling_price: selling_price,
      profit_margin: profit_margin,
      profit_amount: profit_amount,
      stock_status: stock_status,
      stock_value: stock_value,
      average_monthly_consumption: average_monthly_consumption,
      days_of_supply: days_of_supply,
      upcoming_demand: upcoming_demand,
      suggested_reorder_quantity: suggested_reorder_quantity,
      last_transaction_date: inventory_transactions.last&.created_at
    }
  end

  # Inventory check
  def inventory_check(needed_quantity)
    {
      part: self,
      needed: needed_quantity,
      available: current_stock,
      can_fulfill: can_fulfill?(needed_quantity),
      shortfall: needed_quantity > current_stock ? needed_quantity - current_stock : 0,
      status: stock_status,
      status_color: stock_status_color,
      days_of_supply: days_of_supply,
      upcoming_demand: upcoming_demand
    }
  end

  # Check job template usage
  def used_in_job_templates
    job_template_parts.includes(:job_template).map(&:job_template)
  end

  # CSV methods
  def self.import_from_csv(file_path)
    CSV.foreach(file_path, headers: true) do |row|
      part = find_or_initialize_by(part_number: row['part_number']) if row['part_number'].present?
      part ||= find_or_initialize_by(name: row['name'])
      
      part.update(
        name: row['name'],
        description: row['description'],
        category: row['category'],
        part_number: row['part_number'],
        unit_of_measure: row['unit_of_measure'] || 'each',
        cost_price: row['cost_price'],
        current_stock: row['current_stock'] || 0,
        minimum_stock: row['minimum_stock'] || 5,
        reorder_point: row['reorder_point'] || 10,
        lead_time_days: row['lead_time_days'] || 7,
        is_consumable: row['is_consumable'] == 'true',
        location_in_warehouse: row['location_in_warehouse'],
        is_active: row['is_active'] != 'false'
      )
    end
  end

  def to_csv_row
    [
      name,
      part_number,
      description,
      category,
      unit_of_measure,
      cost_price,
      selling_price,
      current_stock,
      minimum_stock,
      reorder_point,
      lead_time_days,
      is_consumable ? 'Yes' : 'No',
      location_in_warehouse,
      is_active ? 'Active' : 'Inactive'
    ]
  end

  def self.csv_headers
    [
      'Name',
      'Part Number',
      'Description',
      'Category',
      'Unit of Measure',
      'Cost Price',
      'Selling Price',
      'Current Stock',
      'Minimum Stock',
      'Reorder Point',
      'Lead Time (Days)',
      'Is Consumable',
      'Location',
      'Status'
    ]
  end

  # Class method for low stock check
  def self.check_low_stock
    low_stock_parts = below_reorder_point
    
    low_stock_parts.each do |part|
      # Only create purchase request if stock is below minimum
      if part.current_stock <= part.minimum_stock
        part.create_purchase_request(urgency: 'high')
      end
      
      # Send notification
      if defined?(Notification)
        Notification.create!(
          title: "Low Stock Alert: #{part.name}",
          message: "Only #{part.current_stock} remaining. Minimum stock: #{part.minimum_stock}",
          level: 'warning',
          actionable: true,
          action_url: Rails.application.routes.url_helpers.vmcott_part_path(part)
        )
      end
    end
    
    low_stock_parts.count
  end

  # Scope for supplier
  def self.by_supplier(supplier_id)
    joins(:supplier).where(supplier_id: supplier_id)
  end
end