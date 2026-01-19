class ZReport < ApplicationRecord
  belongs_to :agency
  belongs_to :user
  belongs_to :cashier_session
  
  before_create :generate_report_number
  
  validates :report_number, presence: true, uniqueness: true
  validates :report_date, presence: true
  
  # Default values
  attribute :starting_cash, :decimal, default: 0.0
  attribute :ending_cash, :decimal, default: 0.0
  attribute :total_sales, :decimal, default: 0.0
  attribute :transaction_count, :integer, default: 0
  attribute :voided_total, :decimal, default: 0.0
  attribute :voided_count, :integer, default: 0
  attribute :refunded_total, :decimal, default: 0.0
  attribute :refunded_count, :integer, default: 0
  attribute :cash_total, :decimal, default: 0.0
  attribute :card_total, :decimal, default: 0.0
  attribute :discrepancy, :decimal, default: 0.0
  
  private
  
  def generate_report_number
    self.report_number ||= "Z-#{report_date.strftime('%Y%m%d')}-#{agency&.code || 'UNK'}-#{SecureRandom.hex(4).upcase}"
  end
end