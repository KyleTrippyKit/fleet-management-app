# app/models/supplier.rb
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
  
  scope :active, -> { where(is_active: true) }
  
  # Search by name, email, or phone - FIXED: Use class method
  def self.search(query = nil)
    return all if query.blank?
    where("name ILIKE ? OR email ILIKE ? OR phone ILIKE ? OR contact_person ILIKE ?",
          "%#{query}%", "%#{query}%", "%#{query}%", "%#{query}%")
  end
  
  def total_outstanding
    vendor_invoices.where(status: ['pending', 'reviewed']).sum(:amount)
  end
  
  def paid_amount
    vendor_invoices.where(status: 'paid').sum(:amount)
  end
  
  def open_invoice_count
    vendor_invoices.where(status: ['pending', 'reviewed']).count
  end
  
  def to_card_data
    {
      name: name,
      email: email,
      phone: phone,
      contact_person: contact_person,
      outstanding_amount: total_outstanding,
      open_invoices: open_invoice_count,
      id: id
    }
  end
end