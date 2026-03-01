# app/models/inspection_job_part.rb
class InspectionJobPart < ApplicationRecord
  belongs_to :inspection_job
  belongs_to :part, optional: true  # Make part optional for custom parts
  
  validates :quantity, presence: true, numericality: { greater_than: 0 }
  
  scope :customer_approved, -> { where(customer_approved: true) }
  scope :pending_approval, -> { where(customer_approved: false) }
  scope :custom_parts, -> { where(part_id: nil) }
  scope :inventory_parts, -> { where.not(part_id: nil) }

  def part_name
    part&.name || custom_part_name
  end

  def custom?
    part_id.nil?
  end

  def inventory?
    part_id.present?
  end

  def approve!
    update(customer_approved: true, customer_approved_at: Time.current)
  end
end