# app/models/inventory_transaction.rb
class InventoryTransaction < ApplicationRecord
  # Associations
  belongs_to :inventory_item, polymorphic: true
  belongs_to :reference, polymorphic: true, optional: true
  belongs_to :user
  belongs_to :agency, optional: true

  # Validations
  validates :quantity, presence: true, numericality: { other_than: 0 }
  validates :transaction_type, presence: true
  validates :user_id, presence: true

  # Enums (Rails 7.1+)
  enum :transaction_type, {
    receipt:    "receipt",
    consumption:"consumption",
    reservation:"reservation",
    release:    "release",
    adjustment: "adjustment",
    transfer:   "transfer",
    stock_in:   "stock_in",
    stock_out:  "stock_out",
    damage:     "damage",
    return:     "return",
    write_off:  "write_off",
    purchase:   "purchase",
    sale:       "sale"
  }

  # Callbacks
  before_validation :calculate_totals
  before_create :track_stock_changes

  # NOTE:
  # We update cached stock after commit so the stock value won't rollback inconsistently.
  after_create_commit :update_inventory_stock
  after_destroy :reverse_inventory_stock

  # Scopes
  scope :recent, -> { order(created_at: :desc) }
  scope :by_item, ->(item) { where(inventory_item: item) }
  scope :by_part, ->(part) { where(inventory_item: part) }
  scope :consumptions, -> { where(transaction_type: "consumption") }
  scope :receipts, -> { where(transaction_type: "receipt") }
  scope :by_date_range, ->(start_date, end_date) {
    where(created_at: start_date.beginning_of_day..end_date.end_of_day)
  }

  # Class methods
  def self.stock_movements_for(part, days: 30)
    where(inventory_item: part)
      .where("created_at >= ?", days.days.ago)
      .order(created_at: :desc)
  end

  # Creates a transaction for a part with sane defaults (unit_price + total_price)
  def self.create_for_part(part, attributes)
    qty = attributes[:quantity].to_f
    unit = part.current_price.to_f

    create(
      attributes.merge(
        inventory_item: part,
        unit_price: unit,
        total_price: unit * qty.abs
      )
    )
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
    if quantity.to_f > 0
      "Stock increased: #{quantity} units"
    else
      "Stock decreased: #{quantity.to_f.abs} units"
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

  # Positive/Negative movement helpers (based on type)
  def is_positive_movement?
    [:receipt, :release, :stock_in, :return, :purchase].include?(transaction_type.to_sym) ||
      (transaction_type.to_sym == :adjustment && quantity.to_f > 0)
  end

  def is_negative_movement?
    [:consumption, :reservation, :stock_out, :damage, :write_off, :sale, :transfer].include?(transaction_type.to_sym) ||
      (transaction_type.to_sym == :adjustment && quantity.to_f < 0)
  end

  def impact_on_stock
    delta_for_stock
  end

  private

  # Compute delta based ONLY on transaction_type.
  # Assumption:
  # - All "normal" transaction quantities are stored POSITIVE.
  # - adjustment can be +/-.
  def delta_for_stock
    case transaction_type.to_sym
    when :receipt, :release, :stock_in, :return, :purchase
      quantity.to_f.abs
    when :consumption, :reservation, :stock_out, :damage, :write_off, :sale, :transfer
      -quantity.to_f.abs
    when :adjustment
      quantity.to_f
    else
      0.0
    end
  end

  def calculate_totals
    return unless unit_price.present? && quantity.present?
    self.total_price = unit_price.to_f * quantity.to_f.abs
  end

  def track_stock_changes
    return unless inventory_item.respond_to?(:current_stock)

    prev = inventory_item.current_stock.to_i
    self.previous_quantity = prev
    self.new_quantity = prev + delta_for_stock.to_i
  end

  def update_inventory_stock
    item = inventory_item
    return unless item.respond_to?(:current_stock)

    new_value = item.current_stock.to_i + delta_for_stock.to_i
    item.update_column(:current_stock, new_value)

    check_low_stock_alert(item)
  end

  def reverse_inventory_stock
    item = inventory_item
    return unless item.respond_to?(:current_stock)

    # Reverse by subtracting the original delta
    new_value = item.current_stock.to_i - delta_for_stock.to_i
    item.update_column(:current_stock, new_value)
  end

  # Low stock alert (crossing logic to avoid spam)
  # Only triggers when stock transitions from ABOVE reorder_point to AT/BELOW reorder_point.
  def check_low_stock_alert(item)
    return unless item.respond_to?(:reorder_point) && item.respond_to?(:current_stock)

    reorder_point = item.reorder_point.to_i
    prev = previous_quantity.to_i
    curr = item.current_stock.to_i

    # ✅ Only alert when we CROSS from safe -> low
    return unless prev > reorder_point && curr <= reorder_point

    if defined?(Notification)
      begin
        Notification.create!(
          title: "Low Stock Alert: #{item.name}",
          message: "Stock level (#{curr}) is at or below reorder point (#{reorder_point})",
          level: "warning",
          actionable: true,
          action_url: Rails.application.routes.url_helpers.part_path(item)
        )
      rescue => e
        Rails.logger.warn("Notification create failed: #{e.class} #{e.message}")
      end
    end

    begin
      LowStockNotificationJob.perform_later(item.id)
    rescue NameError => e
      Rails.logger.warn("LowStockNotificationJob enqueue failed: #{e.class} #{e.message}")
    end
  end
end