# app/models/quotation_line_item.rb
class QuotationLineItem < ApplicationRecord
  belongs_to :quotation

  # ----------------------------
  # Validations
  # ----------------------------
  validates :description, presence: true
  validates :description, length: { maximum: 500 }  # ✅ reject overly-long / garbage rows

  validates :quantity,
            numericality: { only_integer: true, greater_than: 0 }

  validates :unit_price,
            numericality: { greater_than_or_equal_to: 0 }

  # ✅ prevent $0 items once quotation is locked (sent/accepted/rejected/converted)
  validate :nonzero_price_when_locked

  # ----------------------------
  # Callbacks
  # ----------------------------
  before_validation :set_defaults

  # ----------------------------
  # Calculations / Display Helpers
  # ----------------------------
  def total_price
    quantity.to_i * unit_price.to_d
  end

  def formatted_unit_price
    ActionController::Base.helpers.number_to_currency(unit_price.to_d, unit: "$")
  end

  def formatted_total_price
    ActionController::Base.helpers.number_to_currency(total_price, unit: "$")
  end

  private

  def set_defaults
    self.quantity   = 1 if quantity.nil?
    self.unit_price = 0 if unit_price.nil?
  end

  def nonzero_price_when_locked
    return unless quotation&.locked?
    return if unit_price.present? && unit_price.to_d > 0

    errors.add(:unit_price, "must be greater than 0 once sent/accepted")
  end
end
