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
  STATUSES = %w[Pending Completed].freeze
  URGENCIES = %w[routine scheduled emergency].freeze
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
  # Scopes
  # =====================================================
  scope :pending, -> { where(status: "Pending") }
  scope :completed, -> { where(status: "Completed") }
  scope :overdue, -> { pending.where("end_date IS NOT NULL AND end_date < ?", Date.today) }
  scope :upcoming, -> { pending.where("start_date IS NOT NULL AND start_date > ?", Date.today) }
  scope :active, -> { pending.where("start_date IS NOT NULL AND end_date IS NOT NULL AND start_date <= ? AND end_date >= ?", Date.today, Date.today) }
  scope :with_date_range, ->(start_date, end_date) {
    where("start_date IS NOT NULL AND end_date IS NOT NULL AND start_date <= ? AND end_date >= ?", end_date, start_date)
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

  def overdue?
    return false unless pending? && end_date.present?
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
    # Return RGBA format for Chart.js compatibility
    if overdue?
      "rgba(220, 53, 69, 0.8)" # Red for overdue
    elsif completed?
      "rgba(40, 167, 69, 0.8)" # Green for completed
    elsif urgency == "emergency"
      "rgba(253, 126, 20, 0.8)" # Orange for emergency
    elsif urgency == "scheduled"
      "rgba(13, 202, 240, 0.8)" # Teal for scheduled
    else
      "rgba(13, 110, 253, 0.8)" # Blue for routine/default
    end
  end

  # Alternative method that returns hex colors if needed
  def hex_color
    if overdue?
      "#dc3545" # Red
    elsif completed?
      "#28a745" # Green
    elsif urgency == "emergency"
      "#fd7e14" # Orange
    elsif urgency == "scheduled"
      "#0dcaf0" # Teal
    else
      "#0d6efd" # Blue
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
    elsif active?
      "bg-info"
    elsif upcoming?
      "bg-warning"
    else
      "bg-secondary"
    end
  end

  def urgency_badge_class
    case urgency
    when "emergency"
      "bg-danger"
    when "scheduled"
      "bg-warning text-dark"
    when "routine"
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
    update!(status: "Completed")
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

  # =====================================================
  # Display Methods
  # =====================================================
  def display_name
    "#{service_type} - #{vehicle.try(:make)} #{vehicle.try(:model)}"
  end

  def to_s
    "#{service_type} (#{date&.strftime('%Y-%m-%d')})"
  end

  private

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