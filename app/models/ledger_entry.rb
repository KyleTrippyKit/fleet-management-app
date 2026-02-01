# app/models/ledger_entry.rb
class LedgerEntry < ApplicationRecord
  belongs_to :agency
  belongs_to :vehicle
  belongs_to :invoice
  belongs_to :posted_by, class_name: "User", optional: true

  validates :entry_date, :account_code, :account_name, presence: true
  validate :must_have_debit_or_credit

  scope :debits,  -> { where("debit > 0") }
  scope :credits, -> { where("credit > 0") }

  private

  def must_have_debit_or_credit
    d = debit.to_f
    c = credit.to_f

    if d <= 0 && c <= 0
      errors.add(:base, "Ledger entry must have a debit or a credit")
    end

    if d > 0 && c > 0
      errors.add(:base, "Ledger entry cannot have both debit and credit")
    end
  end
end
