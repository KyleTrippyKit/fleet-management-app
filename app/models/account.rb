# app/models/account.rb
class Account < ApplicationRecord
  belongs_to :agency, optional: true
  
  has_many :debit_transactions, class_name: 'AccountTransaction', 
           foreign_key: 'debit_account_id', dependent: :restrict_with_error
  has_many :credit_transactions, class_name: 'AccountTransaction', 
           foreign_key: 'credit_account_id', dependent: :restrict_with_error
  has_many :payables, dependent: :restrict_with_error
  
  # Account types
  ACCOUNT_TYPES = {
    asset: 'asset',
    liability: 'liability',
    equity: 'equity',
    revenue: 'revenue',
    expense: 'expense'
  }.freeze
  
  SUB_TYPES = {
    cash: 'cash',
    bank: 'bank',
    accounts_receivable: 'accounts_receivable',
    accounts_payable: 'accounts_payable',
    credit_card: 'credit_card',
    debit_card: 'debit_card',
    prepaid_expense: 'prepaid_expense',
    inventory: 'inventory',
    fixed_asset: 'fixed_asset',
    accumulated_depreciation: 'accumulated_depreciation',
    loan_payable: 'loan_payable',
    sales_tax_payable: 'sales_tax_payable',
    owner_equity: 'owner_equity',
    retained_earnings: 'retained_earnings',
    sales_revenue: 'sales_revenue',
    service_revenue: 'service_revenue',
    cost_of_goods_sold: 'cost_of_goods_sold',
    payroll_expense: 'payroll_expense',
    rent_expense: 'rent_expense',
    utilities_expense: 'utilities_expense'
  }.freeze
  
  validates :account_number, presence: true, uniqueness: { scope: :agency_id }
  validates :name, presence: true
  validates :account_type, presence: true, inclusion: { in: ACCOUNT_TYPES.values }
  validates :sub_type, inclusion: { in: SUB_TYPES.values }, allow_nil: true
  
  scope :active, -> { where(is_active: true) }
  scope :for_agency, ->(agency_id) { where(agency_id: agency_id) }
  scope :by_type, ->(type) { where(account_type: type) }
  scope :payable_accounts, -> { where(sub_type: 'accounts_payable') }
  scope :bank_accounts, -> { where(sub_type: 'bank') }
  scope :cash_accounts, -> { where(sub_type: 'cash') }
  scope :credit_card_accounts, -> { where(sub_type: 'credit_card') }
  
  before_validation :generate_account_number, on: :create
  
  def self.default_accounts_for_agency(agency)
    accounts = [
      { account_number: '1000', name: 'Cash on Hand', account_type: 'asset', sub_type: 'cash' },
      { account_number: '1010', name: 'Bank Account', account_type: 'asset', sub_type: 'bank' },
      { account_number: '1100', name: 'Accounts Receivable', account_type: 'asset', sub_type: 'accounts_receivable' },
      { account_number: '2000', name: 'Accounts Payable', account_type: 'liability', sub_type: 'accounts_payable' },
      { account_number: '2010', name: 'Credit Card Payable', account_type: 'liability', sub_type: 'credit_card' },
      { account_number: '3000', name: 'Owner\'s Equity', account_type: 'equity', sub_type: 'owner_equity' },
      { account_number: '3100', name: 'Retained Earnings', account_type: 'equity', sub_type: 'retained_earnings' },
      { account_number: '4000', name: 'Sales Revenue', account_type: 'revenue', sub_type: 'sales_revenue' },
      { account_number: '5000', name: 'Cost of Goods Sold', account_type: 'expense', sub_type: 'cost_of_goods_sold' },
      { account_number: '5010', name: 'Vehicle Maintenance Expense', account_type: 'expense', sub_type: 'utilities_expense' }
    ]
    
    accounts.each do |account_attrs|
      find_or_create_by(account_attrs.merge(agency_id: agency.id))
    end
  end
  
  def debit(amount)
    if asset_or_expense?
      update!(balance: balance + amount)
    else
      update!(balance: balance - amount)
    end
  end
  
  def credit(amount)
    if asset_or_expense?
      update!(balance: balance - amount)
    else
      update!(balance: balance + amount)
    end
  end
  
  def asset_or_expense?
    account_type.in?(%w[asset expense])
  end
  
  private
  
  def generate_account_number
    return if account_number.present?
    
    last_account = Account.where(agency_id: agency_id).order(:account_number).last
    if last_account && last_account.account_number.match?(/^\d+$/)
      self.account_number = (last_account.account_number.to_i + 10).to_s.rjust(4, '0')
    else
      self.account_number = '1000'
    end
  end
end