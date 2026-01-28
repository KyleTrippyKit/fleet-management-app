# app/models/job_template_part.rb
class JobTemplatePart < ApplicationRecord
  belongs_to :job_template
  belongs_to :part
  
  validates :quantity, numericality: { greater_than: 0 }
  validates :job_template_id, uniqueness: { scope: :part_id }
  
  # Default values
  attribute :quantity, :integer, default: 1
  attribute :required, :boolean, default: true
  
  # Calculate total price for this part in the template
  def total_price
    quantity * (part.try(:current_price) || 0)
  end
  
  # Check if part is in stock for this template
  def in_stock?
    part&.can_fulfill?(quantity) || false
  end
  
  # Display methods
  def display_name
    "#{part.try(:name)} x#{quantity}"
  end
  
  def display_required
    required ? "Required" : "Optional"
  end
  
  def stock_status
    if in_stock?
      "In Stock (#{part.current_stock} available)"
    else
      "Low Stock (#{part.current_stock} available, need #{quantity})"
    end
  end
  
  # Copy to another job template
  def copy_to_template(target_template)
    target_template.job_template_parts.create!(
      part_id: part_id,
      quantity: quantity,
      required: required,
      notes: notes
    )
  end
end