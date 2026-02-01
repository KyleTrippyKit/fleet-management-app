# app/models/job_template.rb - ENHANCED WITH INVENTORY INTEGRATION + VEHICLE APPLICATIONS
class JobTemplate < ApplicationRecord
  belongs_to :agency

  has_many :job_template_parts, dependent: :destroy
  has_many :parts, through: :job_template_parts
  has_many :quotation_jobs

  # Vehicle matching join table
  has_many :job_template_vehicle_applications, dependent: :destroy

  validates :name, presence: true, uniqueness: { scope: :agency_id }
  validates :agency_id, presence: true

  # LABOR-ONLY templates (no required parts)
  scope :labor_only, -> {
    left_outer_joins(:job_template_parts)
      .where(job_template_parts: { id: nil })
  }
  scope :active, -> { where(is_active: true) }
  scope :by_category, ->(category) { where(category: category) }

  # ============================================
  # VEHICLE MATCHING
  # ============================================

  # Exact match: make + model + year_of_manufacture
  scope :for_vehicle_exact_year, ->(vehicle) do
    return none unless vehicle&.make.present? && vehicle&.model.present? && vehicle&.year_of_manufacture.present?

    joins(:job_template_vehicle_applications)
      .where(job_template_vehicle_applications: {
        make: vehicle.make,
        model: vehicle.model,
        year: vehicle.year_of_manufacture
      })
      .distinct
  end

  # Smart matcher:
  # - Requires make + model
  # - If vehicle year exists, prefer exact-year matches if any exist
  # - Otherwise return make+model matches
  scope :for_vehicle, ->(vehicle) do
    return none unless vehicle&.make.present? && vehicle&.model.present?

    base = joins(:job_template_vehicle_applications)
      .where(job_template_vehicle_applications: {
        make: vehicle.make,
        model: vehicle.model
      })

    if vehicle.year_of_manufacture.present?
      exact = base.where(job_template_vehicle_applications: { year: vehicle.year_of_manufacture })
      exact.exists? ? exact.distinct : base.distinct
    else
      base.distinct
    end
  end

  # Instance helper: does this template apply to a vehicle?
  # Uses exact match when year exists, otherwise make+model.
  def applies_to_vehicle?(vehicle)
    return false unless vehicle&.make.present? && vehicle&.model.present?

    apps = job_template_vehicle_applications
    return false if apps.blank?

    if vehicle.year_of_manufacture.present?
      apps.any? { |a| a.make == vehicle.make && a.model == vehicle.model && a.year == vehicle.year_of_manufacture }
    else
      apps.any? { |a| a.make == vehicle.make && a.model == vehicle.model }
    end
  end

  # ============================================
  # INVENTORY INTEGRATION METHODS
  # ============================================

  def inventory_status
    unavailable_parts = []
    total_needed = 0

    job_template_parts.includes(:part).each do |template_part|
      part = template_part.part
      next unless part

      needed = template_part.quantity
      total_needed += needed

      unless part.can_fulfill?(needed)
        unavailable_parts << {
          part: part,
          needed: needed,
          available: part.current_stock,
          shortfall: needed - part.current_stock,
          part_id: part.id,
          part_name: part.name,
          part_number: part.part_number,
          stock_status: part.stock_status,
          stock_status_color: part.stock_status_color
        }
      end
    end

    {
      all_available: unavailable_parts.empty?,
      unavailable_parts: unavailable_parts,
      total_parts_needed: total_needed,
      unavailable_count: unavailable_parts.count,
      message: unavailable_parts.empty? ? "All parts in stock" : "#{unavailable_parts.count} parts need reordering",
      status: unavailable_parts.empty? ? 'in_stock' : 'low_stock',
      status_color: unavailable_parts.empty? ? 'success' : 'warning'
    }
  end

  def missing_parts
    inventory_status[:unavailable_parts]
  end

  def can_fulfill?
    inventory_status[:all_available]
  end

  def create_purchase_requests_for_missing_parts(urgency: 'normal', requested_by: nil)
    inventory_status[:unavailable_parts].map do |missing|
      missing[:part].create_purchase_request(
        missing[:shortfall],
        urgency: urgency,
        requested_by: requested_by,
        notes: "For job template: #{name}"
      )
    end
  end

  def duplicate(new_name = "#{name} (Copy)")
    new_template = dup
    new_template.name = new_name
    new_template.save!

    job_template_parts.each do |template_part|
      new_template.job_template_parts.create!(
        part_id: template_part.part_id,
        quantity: template_part.quantity,
        notes: template_part.notes,
        required: template_part.required
      )
    end

    # Optional: copy vehicle applications too
    job_template_vehicle_applications.each do |app|
      new_template.job_template_vehicle_applications.create!(
        make: app.make,
        model: app.model,
        year: app.year
      )
    end

    new_template
  end

  # ============================================
  # EXISTING METHODS
  # ============================================

  def default_parts
    job_template_parts.includes(:part).map do |jtp|
      part = jtp.part
      next unless part

      {
        id: part.id,
        name: part.name,
        part_number: part.part_number,
        description: part.description,
        category: part.category,
        quantity: jtp.quantity,
        unit_price: part.current_price,
        total_price: jtp.quantity * part.current_price,
        required: jtp.required != false,
        notes: jtp.notes,
        in_stock: part.can_fulfill?(jtp.quantity),
        available_stock: part.current_stock
      }
    end.compact
  end

  def parts_in_stock?(quantity_multiplier = 1)
    job_template_parts.includes(:part).all? do |jtp|
      next true unless jtp.required != false
      part = jtp.part
      part && part.can_fulfill?(jtp.quantity * quantity_multiplier)
    end
  end

  def missing_parts_list(quantity_multiplier = 1)
    job_template_parts.includes(:part).select do |jtp|
      next false unless jtp.required != false
      part = jtp.part
      next false unless part
      !part.can_fulfill?(jtp.quantity * quantity_multiplier)
    end.map do |jtp|
      part = jtp.part
      {
        job_template_part_id: jtp.id,
        part_id: part.id,
        part_name: part.name,
        part_number: part.part_number,
        needed: jtp.quantity * quantity_multiplier,
        available: part.current_stock,
        shortfall: (jtp.quantity * quantity_multiplier) - part.current_stock,
        required: jtp.required != false
      }
    end
  end

  def total_parts_cost
    job_template_parts.sum do |template_part|
      template_part.quantity * (template_part.part&.current_price || 0)
    end
  end

  def total_labor_cost
    (standard_hours || 0) * (labor_rate_per_hour || 0)
  end

  def total_cost
    total_parts_cost + total_labor_cost
  end

  def suggested_selling_price(markup_percentage = 30.0)
    total_cost * (1 + (markup_percentage / 100.0))
  end

  def create_quotation_job(quotation, options = {})
    quotation_job = quotation.quotation_jobs.build(
      job_template_id: id,
      name: options[:name] || name,
      description: options[:description] || description,
      estimated_hours: options[:hours] || standard_hours || 1,
      labor_rate_per_hour: options[:rate] || labor_rate_per_hour || agency.try(:standard_labor_rate) || 100,
      job_type: 'template',
      priority: options[:priority] || 'medium'
    )

    job_template_parts.includes(:part).each do |jtp|
      next unless jtp.part

      quotation_job.quotation_job_parts.build(
        part_id: jtp.part_id,
        quantity: jtp.quantity,
        unit_price: jtp.part.current_price,
        total_price: jtp.quantity * jtp.part.current_price,
        notes: jtp.notes,
        required: jtp.required != false
      )
    end

    quotation_job
  end

  def labor_cost(rate_per_hour = nil)
    rate = rate_per_hour || labor_rate_per_hour || agency.try(:standard_labor_rate) || 100
    (standard_hours || 1) * rate
  end

  def copy_to_agency(target_agency, copy_parts = true)
    new_template = dup
    new_template.agency = target_agency
    new_template.is_active = true

    if new_template.save && copy_parts
      job_template_parts.each do |jtp|
        new_template.job_template_parts.create!(
          part_id: jtp.part_id,
          quantity: jtp.quantity,
          required: jtp.required,
          notes: jtp.notes
        )
      end
    end

    new_template
  end

  def update_part(part_id, quantity = 1, required = true, notes = nil)
    jtp = job_template_parts.find_or_initialize_by(part_id: part_id)
    jtp.quantity = quantity
    jtp.required = required
    jtp.notes = notes
    jtp.save
  end

  def remove_part(part_id)
    job_template_parts.where(part_id: part_id).destroy_all
  end

  def usage_count
    quotation_jobs.count
  end

  def total_revenue
    quotation_jobs.sum(&:total_labor_cost)
  end

  def add_part(part, quantity = 1, required = true, notes = nil)
    job_template_parts.create!(
      part: part,
      quantity: quantity,
      required: required,
      notes: notes
    )
  end

  def has_part?(part_id)
    job_template_parts.exists?(part_id: part_id)
  end

  def part_quantity(part_id)
    jtp = job_template_parts.find_by(part_id: part_id)
    jtp&.quantity || 0
  end

  def self.import_from_json(json_data, agency)
    templates_data = JSON.parse(json_data)

    templates_data.each do |template_data|
      template = create!(
        agency: agency,
        name: template_data['name'],
        description: template_data['description'],
        category: template_data['category'],
        standard_hours: template_data['standard_hours'],
        labor_rate_per_hour: template_data['labor_rate_per_hour'],
        is_active: true
      )

      if template_data['parts']
        template_data['parts'].each do |part_data|
          part = Part.find_by(name: part_data['name']) || Part.create!(
            name: part_data['name'],
            description: part_data['description'],
            price: part_data['price'],
            category: part_data['category']
          )

          template.job_template_parts.create!(
            part: part,
            quantity: part_data['quantity'] || 1,
            required: part_data['required'] != false,
            notes: part_data['notes']
          )
        end
      end
    end
  end

  def to_json_export
    {
      name: name,
      description: description,
      category: category,
      standard_hours: standard_hours,
      labor_rate_per_hour: labor_rate_per_hour,
      parts: job_template_parts.includes(:part).map do |jtp|
        {
          name: jtp.part.name,
          description: jtp.part.description,
          part_number: jtp.part.part_number,
          category: jtp.part.category,
          quantity: jtp.quantity,
          required: jtp.required,
          notes: jtp.notes
        }
      end
    }
  end

  def display_name
    "#{name} (#{category}) - #{standard_hours} hours"
  end
end
