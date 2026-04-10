# app/models/inspection_job_part.rb
class InspectionJobPart < ApplicationRecord
  belongs_to :inspection_job
  belongs_to :part, optional: true
  belongs_to :dependency_job, class_name: 'InspectionJob', optional: true
  
  validates :quantity, presence: true, numericality: { greater_than: 0 }
    validates :estimated_cost, presence: true, numericality: { greater_than: 0 }

  # Part type enum
  enum :part_type, {
    required: 'required',      # Cannot complete job without this part
    recommended: 'recommended', # Suggested but optional
    optional: 'optional'       # Customer choice
  }, default: 'required'
  
  # ✅ CALLBACKS: Prevent modifications after job approved
  before_create :ensure_job_not_approved
  before_destroy :ensure_job_not_approved
  before_update :ensure_job_not_approved
  
  scope :customer_approved, -> { where(customer_approved: true) }
  scope :pending_approval, -> { where(customer_approved: false) }
  scope :custom_parts, -> { where(part_id: nil) }
  scope :inventory_parts, -> { where.not(part_id: nil) }
  scope :required_parts, -> { where(part_type: 'required') }
  scope :recommended_parts, -> { where(part_type: 'recommended') }
  scope :optional_parts, -> { where(part_type: 'optional') }
  scope :mandatory_parts, -> { where(part_type: 'required').or(where(cannot_complete_without: true)) }

  def part_name
    part&.name || custom_part_name
  end

  def custom?
    part_id.nil?
  end

  def inventory?
    part_id.present?
  end
  
  # Check if this part is mandatory for job completion
  def mandatory?
    part_type == 'required' || cannot_complete_without?
  end

  def approve!
    update(customer_approved: true, customer_approved_at: Time.current)
  end
  
  # ✅ Guard against modifications after job approved
  def ensure_job_not_approved
    if inspection_job.status_in_database == 'approved'
      errors.add(:base, "Cannot modify parts of approved job")
      throw(:abort)
    end
  end
end