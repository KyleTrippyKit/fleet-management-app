class Maintenance < ApplicationRecord
  # =====================================================
  # Associations
  # =====================================================
  belongs_to :vehicle
  belongs_to :assigned_to, class_name: "User", optional: true
  belongs_to :service_provider, optional: true
  has_many :maintenance_tasks, dependent: :destroy

  # =====================================================
  # Constants
  # =====================================================
  ASSIGNMENT_TYPES = %w[stores purchasing].freeze
  STATUSES = %w[Pending Completed In\ Progress].freeze
  URGENCIES = %w[routine scheduled emergency high medium low].freeze
  CATEGORIES = %w[OilChange TireRotation BrakeService EngineCheck Transmission 
                  Electrical BodyWork AirConditioning Suspension General].freeze

  # =====================================================
  # Validations
  # =====================================================
  validates :status, inclusion: { in: STATUSES }
  validates :assignment_type, inclusion: { in: ASSIGNMENT_TYPES }, allow_nil: true
  validates :urgency, inclusion: { in: URGENCIES }, allow_nil: true
  validates :category, inclusion: { in: CATEGORIES }, allow_nil: true
  validates :service_type, presence: true
  validates :date, presence: true
  validates :cost, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  
  validate :end_date_after_start_date
  validate :next_due_date_not_before_date

  # =====================================================
  # Callbacks - Set defaults before validation
  # =====================================================
  before_validation :set_defaults

  # =====================================================
  # Scopes
  # =====================================================
  scope :pending, -> { where(status: "Pending") }
  scope :in_progress, -> { where(status: "In Progress") }
  scope :completed, -> { where(status: "Completed") }
  scope :overdue, -> { 
    where(status: "Pending")
    .where("end_date < ?", Date.today) 
  }
  scope :upcoming, ->(days = 7) { 
    where(status: "Pending")
    .where("end_date BETWEEN ? AND ?", Date.today, Date.today + days)
  }
  scope :active, -> { 
    pending.where("start_date <= ? AND end_date >= ?", Date.today, Date.today) 
  }
  
  scope :with_date_range, ->(start_date, end_date) {
    where("start_date <= ? AND end_date >= ?", end_date, start_date)
  }
  
  scope :by_urgency, ->(urgency_level) { 
    where(urgency: urgency_level) if urgency_level.present? 
  }
  
  scope :by_service_owner, ->(owner) {
    joins(:vehicle).where(vehicles: { service_owner: owner }) if owner.present?
  }

  # =====================================================
  # Status Helpers
  # =====================================================
  def completed?
    status == "Completed"
  end

  def pending?
    status == "Pending"
  end
  
  def in_progress?
    status == "In Progress"
  end

  # FIXED: Simplified overdue? method to match what controller expects
  def overdue?
    return false if status == 'Completed'
    return false unless end_date
    end_date < Date.today
  end

  def upcoming?
    return false unless pending? && start_date.present?
    start_date > Date.today
  end

  def active?
    return false unless pending? && start_date.present? && end_date.present?
    start_date <= Date.today && end_date >= Date.today
  end

  # =====================================================
  # Timeline Methods - UPDATED FOR GANTT CHART
  # =====================================================
  def gantt_bar_color
    # FIXED: Return hex colors for DHTMLX Gantt compatibility
    if overdue?
      "#dc3545" # Red for overdue
    elsif completed?
      "#198754" # Green for completed
    elsif urgency == "emergency" || urgency == "high"
      "#fd7e14" # Orange for emergency/high
    elsif urgency == "scheduled" || urgency == "medium"
      "#0dcaf0" # Teal for scheduled/medium
    else
      "#0d6efd" # Blue for routine/low
    end
  end

  # Alternative method that returns RGBA format for Chart.js
  def rgba_color
    if overdue?
      "rgba(220, 53, 69, 0.8)" # Red
    elsif completed?
      "rgba(40, 167, 69, 0.8)" # Green
    elsif urgency == "emergency" || urgency == "high"
      "rgba(253, 126, 20, 0.8)" # Orange
    elsif urgency == "scheduled" || urgency == "medium"
      "rgba(13, 202, 240, 0.8)" # Teal
    else
      "rgba(13, 110, 253, 0.8)" # Blue
    end
  end

  def duration_days
    return 0 unless start_date && end_date
    (end_date - start_date).to_i + 1
  end

  def progress_percentage
    return 100 if completed?
    return 0 if start_date.blank? || end_date.blank?
    return 0 if start_date > Date.today
    
    total_days = duration_days
    days_elapsed = [0, (Date.today - start_date).to_i].max
    [100, (days_elapsed.to_f / total_days * 100).round].min
  end

  def status_badge_class
    if completed?
      "bg-success"
    elsif overdue?
      "bg-danger"
    elsif in_progress?
      "bg-info"
    elsif active?
      "bg-primary"
    elsif upcoming?
      "bg-warning"
    else
      "bg-secondary"
    end
  end

  def urgency_badge_class
    case urgency
    when "emergency", "high"
      "bg-danger"
    when "scheduled", "medium"
      "bg-warning text-dark"
    when "routine", "low"
      "bg-primary"
    else
      "bg-secondary"
    end
  end

  def display_dates
    if start_date.blank? || end_date.blank?
      date&.strftime("%b %d, %Y") || "No dates set"
    elsif start_date == end_date
      start_date.strftime("%b %d, %Y")
    else
      "#{start_date.strftime("%b %d")} - #{end_date.strftime("%b %d, %Y")}"
    end
  end

  # Helper method for JSON date formatting
  def start_date_iso
    start_date&.iso8601
  end

  def end_date_iso
    end_date&.iso8601
  end

  # =====================================================
  # Reminder Helpers
  # =====================================================
  def reminder_status
    return "Completed" if completed?
    return "Overdue" if overdue?
    return "Active" if active?
    return "Starting Soon" if start_date.present? && start_date <= Date.today + 3.days
    return "Upcoming" if start_date.present? && start_date <= Date.today + 30.days
    "Scheduled"
  end

  # =====================================================
  # CSV Export
  # =====================================================
  def self.csv_headers
    ["Vehicle", "Registration", "Service Type", "Start Date", "End Date", 
     "Duration", "Status", "Urgency", "Cost", "Notes"]
  end

  def to_csv_row
    [
      vehicle.display_name,
      vehicle.registration_number,
      service_type,
      start_date&.strftime("%Y-%m-%d") || "",
      end_date&.strftime("%Y-%m-%d") || "",
      duration_days,
      status,
      urgency || "",
      cost || 0,
      notes || ""
    ]
  end

  # =====================================================
  # Action Methods
  # =====================================================
  def mark_completed!
    update!(status: "Completed", end_date: Date.today)
  end

  def schedule_next(miles_interval: 5000, days_interval: 180)
    return unless completed? && mileage && end_date
    
    next_start = end_date + days_interval.days
    next_end = next_start + 7.days # Default 1 week duration
    next_mileage = mileage + miles_interval
    
    Maintenance.create!(
      vehicle: vehicle,
      service_type: service_type,
      status: "Pending",
      start_date: next_start,
      end_date: next_end,
      date: next_start,
      next_due_date: next_end,
      mileage: next_mileage,
      urgency: "scheduled",
      notes: "Automatically scheduled - Next service"
    )
  end

  # =====================================================
  # Gantt Chart Data Methods
  # =====================================================
  def gantt_task_data
    {
      id: "maintenance_#{id}",
      name: service_type.presence || "Maintenance ##{id}",
      start: start_date&.to_s || Date.today.to_s,
      end: end_date&.to_s || (Date.today + 7.days).to_s,
      parent: "vehicle_#{vehicle_id}",
      type: 'maintenance',
      color: gantt_bar_color,
      details: {
        status: status || 'Pending',
        urgency: urgency || 'routine',
        cost: cost.to_f || 0,
        notes: notes.to_s,
        vehicle_id: vehicle_id,
        maintenance_id: id,
        duration: duration_days
      }
    }
  end

  # NEW: Method specifically for DHTMLX Gantt format
  def dhtmlx_gantt_data
    {
      id: "maintenance_#{id}",
      text: service_type.presence || "Maintenance ##{id}",
      start_date: start_date&.strftime("%Y-%m-%d") || Date.today.strftime("%Y-%m-%d"),
      end_date: end_date&.strftime("%Y-%m-%d") || (Date.today + 7.days).strftime("%Y-%m-%d"),
      parent: "vehicle_#{vehicle_id}",
      progress: completed? ? 1 : 0.5,
      open: true,
      color: gantt_bar_color,
      status: status || 'Pending',
      urgency: urgency || 'routine',
      overdue: overdue?,
      details: {
        status: status || 'Pending',
        urgency: urgency || 'routine',
        cost: cost.to_f || 0,
        notes: notes.to_s,
        vehicle_id: vehicle_id,
        maintenance_id: id,
        duration: duration_days,
        service_type: service_type,
        category: category
      }
    }
  end

  # =====================================================
  # Display Methods
  # =====================================================
  def display_name
    "#{service_type} - #{vehicle.try(:make)} #{vehicle.try(:model)}"
  end

  def to_s
    "#{service_type} (#{date&.strftime('%Y-%m-%d')})"
  end

  # =====================================================
  # Urgency Helper for Views
  # =====================================================
  def urgency_display
    urgency&.titleize || "Normal"
  end

  # =====================================================
  # Owner field (for filtering)
  # =====================================================
  # This is a virtual attribute or delegate method
  def owner
    # You can either store this directly on Maintenance or get it from Vehicle
    self[:owner] || vehicle&.service_owner
  end

  def owner=(value)
    self[:owner] = value
  end

  private

  # =====================================================
  # Set default values
  # =====================================================
  def set_defaults
    self.assignment_type ||= 'stores' if assignment_type.nil?
    self.urgency ||= 'routine' if urgency.nil?
    self.status ||= 'Pending' if status.nil?
    self.date ||= Date.today if date.nil?
    self.start_date ||= Date.today if start_date.nil?
    self.end_date ||= (Date.today + 7.days) if end_date.nil?
    self.owner ||= vehicle&.service_owner if owner.nil?
  end

  # =====================================================
  # Custom Validations
  # =====================================================
  def end_date_after_start_date
    return if start_date.blank? || end_date.blank?
    if end_date < start_date
      errors.add(:end_date, "must be after start date")
    end
  end

  def next_due_date_not_before_date
    return if next_due_date.blank? || date.blank?
    if next_due_date < date
      errors.add(:next_due_date, "cannot be before the maintenance date")
    end
  end
end