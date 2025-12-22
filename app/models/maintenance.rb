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
  STATUSES        = %w[Pending Completed].freeze
  URGENCIES       = %w[routine scheduled emergency].freeze
  CATEGORIES      = %w[OilChange TireRotation BrakeService EngineCheck Transmission 
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
  
  validate :next_due_date_not_before_date

  # =====================================================
  # Scopes
  # =====================================================
  scope :pending, -> { where(status: "Pending") }
  scope :completed, -> { where(status: "Completed") }
  scope :overdue, -> { pending.where("next_due_date < ?", Date.today) }
  scope :due_today, -> { pending.where(next_due_date: Date.today) }
  scope :upcoming, -> { pending.where(next_due_date: Date.today..30.days.from_now) }
  scope :without_due_date, -> { where(next_due_date: nil) }
  scope :by_urgency, ->(urgency) { where(urgency: urgency) if urgency.present? }
  scope :by_category, ->(category) { where(category: category) if category.present? }
  
  # For Gantt chart
  scope :with_date_range, ->(start_date, end_date) {
    where("(start_date BETWEEN ? AND ?) OR (end_date BETWEEN ? AND ?) OR (next_due_date BETWEEN ? AND ?)", 
          start_date, end_date, start_date, end_date, start_date, end_date)
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

  # For gantt chart and overdue calculations
  def overdue?
    return false if completed? || next_due_date.nil?
    next_due_date < Date.today
  end

  # =====================================================
  # Assignment Helpers
  # =====================================================
  def assignment_type_stores?
    assignment_type == "stores"
  end

  def assignment_type_purchasing?
    assignment_type == "purchasing"
  end

  # =====================================================
  # Urgency Helpers
  # =====================================================
  def urgency_routine?
    urgency == "routine"
  end

  def urgency_scheduled?
    urgency == "scheduled"
  end

  def urgency_emergency?
    urgency == "emergency"
  end

  # Display-friendly urgency label
  def urgency_label
    case urgency
    when "routine"   then "Routine"
    when "scheduled" then "Scheduled"
    when "emergency" then "Emergency"
    else "Not specified"
    end
  end

  # Badge color class for urgency
  def urgency_badge_class
    case urgency
    when "routine"   then "bg-primary"
    when "scheduled" then "bg-warning text-dark"
    when "emergency" then "bg-danger"
    else "bg-secondary"
    end
  end

  # =====================================================
  # Gantt Chart & Timeline Methods
  # =====================================================
  # Start date for gantt chart (uses start_date if available, otherwise date)
  def gantt_start_date
    start_date || date || Date.today
  end

  # End date for gantt chart (uses end_date if available, otherwise next_due_date or date+7 days)
  def gantt_end_date
    end_date || next_due_date || (date || Date.today) + 7.days
  end

  # Duration in days for gantt chart
  def gantt_duration_days
    (gantt_end_date - gantt_start_date).to_i + 1
  end

  # Color for gantt chart bars
  def gantt_bar_color
    if overdue?
      "#dc3545" # Red for overdue
    elsif completed?
      "#28a745" # Green for completed
    elsif urgency == "emergency"
      "#fd7e14" # Orange for emergency
    elsif urgency == "scheduled"
      "#0dcaf0" # Teal for scheduled
    else
      "#0d6efd" # Blue for routine/default
    end
  end

  # Time period classification for folders
  def time_period_class
    today = Date.today
    diff_days = (gantt_start_date - today).to_i
    
    if diff_days <= 7
      "this_week"
    elsif diff_days <= 14
      "next_week"
    elsif diff_days <= 30
      "this_month"
    else
      "future"
    end
  end

  # Technician/Service provider name for display
  def technician_name
    technician.presence || service_provider&.name || 'Unassigned'
  end

  # Gantt task data structure
  def to_gantt_task(vehicle_id:, folder_id:)
    {
      id: "maintenance_#{id}",
      name: service_type.to_s,
      start: gantt_start_date.strftime("%Y-%m-%d"),
      end: gantt_end_date.strftime("%Y-%m-%d"),
      parent: folder_id,
      type: 'maintenance',
      color: gantt_bar_color,
      details: {
        status: status,
        technician: technician_name,
        cost: cost,
        urgency: urgency,
        vehicle_id: vehicle_id,
        maintenance_id: id,
        notes: notes.to_s
      }
    }
  end

  # =====================================================
  # Dashboard & Timeline Logic
  # =====================================================
  def urgency_level
    return :completed if completed?
    return :overdue if overdue?
    return :na if next_due_date.blank?
    
    days_until = (next_due_date - Date.today).to_i
    
    return :critical if days_until < 0
    return :soon if days_until <= 7
    return :upcoming if days_until <= 30
    :ok
  end

  def urgency_display_text
    case urgency_level
    when :completed then "Completed"
    when :overdue, :critical then "Overdue #{days_overdue.abs}d"
    when :soon      then "Due in #{days_until} days"
    when :upcoming  then "Upcoming"
    when :na        then "No due date"
    else "On track"
    end
  end

  def urgency_display_class
    case urgency_level
    when :completed then "bg-success"
    when :overdue, :critical then "bg-danger"
    when :soon      then "bg-warning text-dark"
    when :upcoming  then "bg-info"
    when :na        then "bg-secondary"
    else "bg-success"
    end
  end

  def days_overdue
    return 0 unless next_due_date && overdue?
    (Date.today - next_due_date).to_i
  end

  def days_until
    return 0 unless next_due_date && !completed?
    (next_due_date - Date.today).to_i
  end

  # =====================================================
  # Reminder Helpers
  # =====================================================
  def reminder_status
    return "Completed" if completed?
    return "Overdue" if overdue?
    return "Due Today" if next_due_date == Date.today
    return "Due Soon" if next_due_date && next_due_date <= 7.days.from_now
    return "Upcoming" if next_due_date && next_due_date <= 30.days.from_now
    "Scheduled"
  end

  # =====================================================
  # Mileage Helpers
  # =====================================================
  def mileage_until_next_service(interval = 5000)
    return nil unless mileage && vehicle&.mileage
    next_service_mileage = mileage + interval
    next_service_mileage - vehicle.mileage
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
  # State Transitions
  # =====================================================
  def mark_completed!
    update!(
      status: "Completed",
      next_due_date: nil
    )
  end

  def schedule_next(miles_interval: 5000, days_interval: 180)
    return unless completed? && mileage && date
    
    next_mileage = mileage + miles_interval
    next_date = date + days_interval.days
    
    self.class.create!(
      vehicle: vehicle,
      service_type: service_type,
      status: "Pending",
      date: next_date,
      next_due_date: next_date,
      mileage: next_mileage,
      urgency: "scheduled",
      notes: "Automatically scheduled - Next service at #{next_mileage} miles"
    )
  end

  # =====================================================
  # Import/Export Helpers
  # =====================================================
  def to_csv_row
    [
      vehicle.try(:registration_number),
      vehicle.try(:make),
      vehicle.try(:model),
      service_type,
      date&.strftime("%Y-%m-%d"),
      next_due_date&.strftime("%Y-%m-%d"),
      status,
      urgency_label,
      cost,
      service_provider&.name,
      notes
    ]
  end

  def self.csv_headers
    ["Registration", "Make", "Model", "Service Type", "Date", "Next Due", "Status", 
     "Urgency", "Cost", "Service Provider", "Notes"]
  end

  private

  # =====================================================
  # Custom Validations
  # =====================================================
  def next_due_date_not_before_date
    return if next_due_date.blank? || date.blank?
    if next_due_date < date
      errors.add(:next_due_date, "cannot be before the maintenance date")
    end
  end
end