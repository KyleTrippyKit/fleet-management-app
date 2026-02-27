class Maintenance < ApplicationRecord
  # =====================================================
  # Associations
  # =====================================================
  belongs_to :vehicle
  belongs_to :assigned_to, class_name: "User", optional: true
  belongs_to :service_provider, optional: true
  has_many :maintenance_tasks, dependent: :destroy

  # =====================================================
  # Constants - REMOVE URGENCIES constant since we're using enum differently
  # =====================================================
  ASSIGNMENT_TYPES = %w[stores purchasing].freeze
  STATUSES = %w[Pending Completed In\ Progress].freeze
  
  # REMOVE THIS: URGENCIES constant
  # URGENCIES = {
  #   routine: 0,
  #   scheduled: 1, 
  #   emergency: 2,
  #   high: 3,
  #   medium: 4,
  #   low: 5
  # }.freeze
  
  CATEGORIES = %w[OilChange TireRotation BrakeService EngineCheck Transmission 
                  Electrical BodyWork AirConditioning Suspension General].freeze

  # =====================================================
  # Enums - CORRECT SYNTAX (Simplified)
  # =====================================================
  # Option A: Simple enum (Rails will auto-assign 0, 1, 2, etc.)
  enum :urgency, {
    routine: 0,
    scheduled: 1,
    emergency: 2,
    high: 3,
    medium: 4,
    low: 5
  }, default: :routine

  # =====================================================
  # Validations - REMOVE urgency validation (enum handles it)
  # =====================================================
  validates :status, inclusion: { in: STATUSES }
  validates :assignment_type, inclusion: { in: ASSIGNMENT_TYPES }, allow_nil: true
  validates :category, inclusion: { in: CATEGORIES }, allow_nil: true
  validates :service_type, presence: true
  validates :date, presence: true
  validates :start_date, presence: true
  validates :end_date, presence: true
  validates :cost, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  
  validate :end_date_after_start_date
  validate :next_due_date_not_before_date

  # =====================================================
  # Callbacks - UPDATED: Set defaults BEFORE validation
  # =====================================================
  before_validation :set_defaults

  # =====================================================
  # Scopes - UPDATE by_urgency to use integer values
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
  
  # UPDATE: by_urgency scope to work with enum
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
  # Safe Date Methods
  # =====================================================
  def safe_date
    date || Date.today
  end

  def safe_start_date
    start_date || Date.today
  end

  def safe_end_date
    end_date || (Date.today + 7.days)
  end

  attr_accessor :next_maintenance_mileage
  # =====================================================
  # Timeline Methods - USE enum predicate methods
  # =====================================================
  def gantt_bar_color
    if overdue?
      "#dc3545" # Red for overdue
    elsif completed?
      "#198754" # Green for completed
    elsif emergency? || high?
      "#fd7e14" # Orange for emergency/high
    elsif scheduled? || medium?
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
    elsif emergency? || high?
      "rgba(253, 126, 20, 0.8)" # Orange
    elsif scheduled? || medium?
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
    # Use enum predicate methods
    if emergency? || high?
      "bg-danger"
    elsif scheduled? || medium?
      "bg-warning text-dark"
    elsif routine? || low?
      "bg-primary"
    else
      "bg-secondary"
    end
  end

  def display_dates
    if start_date.blank? || end_date.blank?
      safe_date.strftime("%b %d, %Y") || "No dates set"
    elsif start_date == end_date
      safe_start_date.strftime("%b %d, %Y")
    else
      "#{safe_start_date.strftime("%b %d")} - #{safe_end_date.strftime("%b %d, %Y")}"
    end
  end

  # Helper method for JSON date formatting
  def start_date_iso
    safe_start_date.iso8601
  end

  def end_date_iso
    safe_end_date.iso8601
  end

  # =====================================================
  # Gantt Chart Methods
  # =====================================================
  def gantt_datasets
    {
      label: "#{details} (#{status})",
      backgroundColor: status == 'Completed' ? 'rgba(75, 192, 192, 0.7)' : 'rgba(255, 99, 132, 0.7)',
      data: [{
        x: safe_start_date.strftime("%Y-%m-%d"),
        x2: safe_end_date.strftime("%Y-%m-%d"),
        y: "#{vehicle.try(:make)} - #{vehicle.try(:license_plate)}"
      }]
    }
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
      safe_start_date.strftime("%Y-%m-%d"),
      safe_end_date.strftime("%Y-%m-%d"),
      duration_days,
      status,
      urgency_display,
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
      urgency: :scheduled,
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
      start: safe_start_date.to_s,
      end: safe_end_date.to_s,
      parent: "vehicle_#{vehicle_id}",
      type: 'maintenance',
      color: gantt_bar_color,
      details: {
        status: status || 'Pending',
        urgency: urgency_display,
        cost: cost.to_f || 0,
        notes: notes.to_s,
        vehicle_id: vehicle_id,
        maintenance_id: id,
        duration: duration_days
      }
    }
  end

  # Method specifically for DHTMLX Gantt format
  def dhtmlx_gantt_data
    {
      id: "maintenance_#{id}",
      text: service_type.presence || "Maintenance ##{id}",
      start_date: safe_start_date.strftime("%Y-%m-%d"),
      end_date: safe_end_date.strftime("%Y-%m-%d"),
      parent: "vehicle_#{vehicle_id}",
      progress: completed? ? 1 : 0.5,
      open: true,
      color: gantt_bar_color,
      status: status || 'Pending',
      urgency: urgency_display,
      overdue: overdue?,
      details: {
        status: status || 'Pending',
        urgency: urgency_display,
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
    "#{service_type} (#{safe_date.strftime('%Y-%m-%d')})"
  end

  # =====================================================
  # Urgency Helper for Views
  # =====================================================
  def urgency_display
    # This will automatically use the humanized enum value
    urgency&.humanize || "Normal"
  end

  # =====================================================
  # Owner field (for filtering)
  # =====================================================
  def owner
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
    self.date ||= Date.today if date.nil?
    self.start_date ||= Date.today if start_date.nil?
    self.end_date ||= (Date.today + 7.days) if end_date.nil?
    self.status ||= 'Pending' if status.nil?
    self.urgency ||= :routine if self[:urgency].nil?  # Use symbol for enum
    self.assignment_type ||= 'stores' if assignment_type.nil?
    self.category ||= 'General' if category.nil?
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