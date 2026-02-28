# app/models/inspection.rb
class Inspection < ApplicationRecord
  belongs_to :vehicle
  belongs_to :inspector, class_name: 'User'
  belongs_to :purchase_order, optional: true
  
  has_many :inspection_jobs, dependent: :destroy
  has_many :job_templates, through: :inspection_jobs
  
  accepts_nested_attributes_for :inspection_jobs, allow_destroy: true
  
  validates :inspector_id, presence: true
  validates :vehicle_id, presence: true
  validates :mileage_at_inspection, numericality: { greater_than: 0 }, allow_nil: true
  
  scope :pending, -> { where(completed_at: nil) }
  scope :completed, -> { where.not(completed_at: nil) }
  
  def completed?
    completed_at.present?
  end
  
  def total_estimated_cost
    inspection_jobs.sum(&:estimated_total)
  end
  
  def create_purchase_order_from_jobs(created_by_user)
    return if purchase_order.present?
    
    po = PurchaseOrder.create!(
      vehicle: vehicle,
      vendor: 'VMCOTT',
      amount: total_estimated_cost,
      status: 'draft',
      created_by: created_by_user,
      notes: "Created from inspection ##{id} on #{created_at.strftime('%B %d, %Y')}",
      acceptance_status: 'pending_acceptance'
    )
    
    inspection_jobs.each do |job|
      po.purchase_order_items.create!(
        description: job.description,
        quantity: 1,
        unit_price: job.estimated_total,
        notes: job.notes,
        is_accepted: nil
      )
      
      # Add parts from job template
      if job.job_template.present?
        job.job_template.job_template_parts.each do |template_part|
          po.purchase_order_items.create!(
            part_id: template_part.part_id,
            description: "Part for #{job.description}: #{template_part.part.name}",
            quantity: template_part.quantity,
            unit_price: template_part.part.current_price,
            is_accepted: nil
          )
        end
      end
    end
    
    po.recalculate_amount!
    po
  end
  
  def recommend_next_service
    return unless mileage_at_inspection.present? && next_service_mileage.present?
    
    {
      current_mileage: mileage_at_inspection,
      next_service_at: next_service_mileage,
      kilometers_remaining: next_service_mileage - mileage_at_inspection,
      estimated_date: next_service_date
    }
  end
end