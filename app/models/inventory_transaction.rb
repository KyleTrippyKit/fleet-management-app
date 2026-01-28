# app/models/inventory_transaction.rb
class InventoryTransaction < ApplicationRecord
  # Associations
  belongs_to :inventory_item, polymorphic: true
  belongs_to :reference, polymorphic: true, optional: true
  belongs_to :user
  belongs_to :agency, optional: true  # Make this optional since not all transactions might have an agency
  
  # Validations
  validates :quantity, presence: true, numericality: { other_than: 0 }
  validates :transaction_type, presence: true
  validates :user_id, presence: true
  
  # Enums - using Rails 7.1+ syntax
  enum :transaction_type, {
    receipt: 'receipt',
    consumption: 'consumption',
    reservation: 'reservation',
    release: 'release',
    adjustment: 'adjustment',
    transfer: 'transfer',
    stock_in: 'stock_in',
    stock_out: 'stock_out',
    damage: 'damage',
    return: 'return',
    write_off: 'write_off',
    purchase: 'purchase',
    sale: 'sale'
  }
  
  # Callbacks
  before_validation :calculate_totals
  before_create :track_stock_changes
  after_create :update_inventory_stock
  after_destroy :reverse_inventory_stock
  
  # Scopes
  scope :recent, -> { order(created_at: :desc) }
  scope :by_item, ->(item) { where(inventory_item: item) }
  scope :by_part, ->(part) { where(inventory_item: part) }
  scope :consumptions, -> { where(transaction_type: 'consumption') }
  scope :receipts, -> { where(transaction_type: 'receipt') }
  scope :by_date_range, ->(start_date, end_date) { 
    where(created_at: start_date.beginning_of_day..end_date.end_of_day) 
  }
  
  # Class methods
  def self.stock_movements_for(part, days: 30)
    where(inventory_item: part)
      .where('created_at >= ?', days.days.ago)
      .order(created_at: :desc)
  end
  
  def self.create_for_part(part, attributes)
    create(attributes.merge(
      inventory_item: part,
      unit_price: part.current_price,
      total_price: attributes[:quantity] * part.current_price
    ))
  end
  
  # Instance methods
  def description
    case transaction_type.to_sym
    when :receipt, :stock_in
      "Stock received: #{quantity} units"
    when :consumption, :stock_out
      "Stock consumed: #{quantity} units"
    when :reservation
      "Stock reserved: #{quantity} units"
    when :release
      "Stock released: #{quantity} units"
    when :adjustment
      adjustment_description
    when :transfer
      "Stock transferred: #{quantity} units"
    when :damage
      "Stock damaged: #{quantity} units"
    when :return
      "Stock returned: #{quantity} units"
    when :write_off
      "Stock written off: #{quantity} units"
    when :purchase
      "Purchase: #{quantity} units"
    when :sale
      "Sale: #{quantity} units"
    else
      "Stock transaction: #{quantity} units"
    end
  end
  
  def adjustment_description
    if quantity > 0
      "Stock increased: #{quantity} units"
    else
      "Stock decreased: #{-quantity} units"
    end
  end
  
  def formatted_unit_price
    ActionController::Base.helpers.number_to_currency(unit_price || 0)
  end
  
  def formatted_total_price
    ActionController::Base.helpers.number_to_currency(total_price || 0)
  end
  
  def stock_change_description
    if previous_quantity.present? && new_quantity.present?
      "#{previous_quantity} → #{new_quantity}"
    else
      "N/A"
    end
  end
  
  def is_positive_movement?
    [:receipt, :release, :stock_in, :return, :purchase].include?(transaction_type.to_sym) || 
    (transaction_type.to_sym == :adjustment && quantity > 0)
  end
  
  def is_negative_movement?
    [:consumption, :reservation, :stock_out, :damage, :write_off, :sale].include?(transaction_type.to_sym) ||
    (transaction_type.to_sym == :adjustment && quantity < 0)
  end
  
  def impact_on_stock
    if is_positive_movement?
      quantity.abs
    elsif is_negative_movement?
      -quantity.abs
    else
      0
    end
  end
  
  private
  
  def calculate_totals
    if unit_price.present? && quantity.present?
      self.total_price = unit_price * quantity.abs
    end
  end
  
  def track_stock_changes
    # Track quantity changes if inventory_item supports it
    if inventory_item.respond_to?(:current_stock)
      self.previous_quantity = inventory_item.current_stock
      
      # Calculate new quantity based on transaction type
      case transaction_type.to_sym
      when :receipt, :release, :stock_in, :return, :purchase
        self.new_quantity = previous_quantity + quantity.abs
      when :consumption, :reservation, :stock_out, :damage, :write_off, :sale
        self.new_quantity = previous_quantity - quantity.abs
      when :adjustment
        self.new_quantity = previous_quantity + quantity # quantity can be positive or negative
      when :transfer
        # For transfers, we're moving stock out from this location
        self.new_quantity = previous_quantity - quantity.abs
      end
    end
  end
  
  def update_inventory_stock
    item = inventory_item
    
    return unless item.respond_to?(:current_stock)
    
    case transaction_type.to_sym
    when :receipt, :release, :stock_in, :return, :purchase
      item.update_column(:current_stock, item.current_stock + quantity.abs)
    when :consumption, :reservation, :stock_out, :damage, :write_off, :sale
      item.update_column(:current_stock, item.current_stock - quantity.abs)
    when :adjustment
      item.update_column(:current_stock, item.current_stock + quantity) # quantity can be positive or negative
    when :transfer
      # For transfers, we're moving stock out from this location
      item.update_column(:current_stock, item.current_stock - quantity.abs)
    end
    
    # Check for low stock alerts after update
    check_low_stock_alert(item)
  end
  
  def reverse_inventory_stock
    item = inventory_item
    
    return unless item.respond_to?(:current_stock)
    
    case transaction_type.to_sym
    when :receipt, :release, :stock_in, :return, :purchase
      item.update_column(:current_stock, item.current_stock - quantity.abs)
    when :consumption, :reservation, :stock_out, :damage, :write_off, :sale
      item.update_column(:current_stock, item.current_stock + quantity.abs)
    when :adjustment
      item.update_column(:current_stock, item.current_stock - quantity) # Reverse the adjustment
    when :transfer
      item.update_column(:current_stock, item.current_stock + quantity.abs)
    end
  end
  
  def check_low_stock_alert(item)
    return unless item.respond_to?(:reorder_point) && item.respond_to?(:current_stock)
    
    if item.current_stock <= item.reorder_point
      # Create notification
      if defined?(Notification)
        Notification.create!(
          title: "Low Stock Alert: #{item.name}",
          message: "Stock level (#{item.current_stock}) is at or below reorder point (#{item.reorder_point})",
          level: 'warning',
          actionable: true,
          action_url: Rails.application.routes.url_helpers.part_path(item)
        )
      end
      
      # Send email alert to VMCOTT users
      if defined?(LowStockNotificationJob)
        LowStockNotificationJob.perform_later(item)
      end
    end
  end
end