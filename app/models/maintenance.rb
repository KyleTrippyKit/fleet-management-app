# app/models/maintenance.rb
class Maintenance < ApplicationRecord
  # =====================================================
  # Associations
  # =====================================================
  belongs_to :vehicle
  belongs_to :assigned_to, class_name: "User", optional: true
  belongs_to :service_provider, optional: true
  belongs_to :parent_maintenance, class_name: "Maintenance", optional: true
  belongs_to :quotation, optional: true
  
  has_many :maintenance_tasks, dependent: :destroy
  has_many :child_maintenances, class_name: "Maintenance", foreign_key: "parent_maintenance_id"

  # =====================================================
  # Enums
  # =====================================================
  enum :urgency, {
    routine: 0,
    scheduled: 1,
    emergency: 2,
    high: 3,
    medium: 4,
    low: 5
  }, default: :routine

  # =====================================================
  # Validations
  # =====================================================
  validates :status, inclusion: { in: %w[Pending Completed In\ Progress] }
  validates :assignment_type, inclusion: { in: %w[stores purchasing] }, allow_nil: true
  validates :category, inclusion: { in: %w[OilChange TireRotation BrakeService EngineCheck Transmission 
                                            Electrical BodyWork AirConditioning Suspension General] }, allow_nil: true
  validates :service_type, presence: true
  validates :date, presence: true
  validates :start_date, presence: true
  validates :end_date, presence: true
  validates :cost, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  
  validate :end_date_after_start_date
  validate :next_due_date_not_before_date

  # =====================================================
  # Callbacks
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

  # NEW: Scope for additional work
  scope :additional_work, -> { where(additional_work: true) }
  scope :original_work, -> { where(additional_work: false) }
  
  # NEW: Scope for agency decisions
  scope :cancelled_by_agency, -> { where(cancelled_by_agency: true) }

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

  # NEW: Check if this is additional work
  def additional_work?
    additional_work == true
  end

  # NEW: Get original maintenance if this is additional work
  def original_maintenance
    parent_maintenance if additional_work?
  end

  # NEW: Get all additional work for this maintenance
  def additional_work_items
    child_maintenances if !additional_work?
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
  # Timeline Methods
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

  def gantt_task_data
    {
      id: "maintenance_#{id}",
      name: service_type.presence || "Maintenance ##{id}",
      start: safe_start_date.to_s,
      end: safe_end_date.to_s,
      parent: "vehicle_#{vehicle_id}",
      type: 'maintenance',
      color: gantt_bar_color,
      additional_work: additional_work?,
      details: {
        status: status || 'Pending',
        urgency: urgency_display,
        cost: cost.to_f || 0,
        notes: notes.to_s,
        vehicle_id: vehicle_id,
        maintenance_id: id,
        duration: duration_days,
        additional_work: additional_work?
      }
    }
  end

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
      additional_work: additional_work?,
      details: {
        status: status || 'Pending',
        urgency: urgency_display,
        cost: cost.to_f || 0,
        notes: notes.to_s,
        vehicle_id: vehicle_id,
        maintenance_id: id,
        duration: duration_days,
        service_type: service_type,
        category: category,
        additional_work: additional_work?
      }
    }
  end

  # =====================================================
  # Display Methods
  # =====================================================
  def display_name
    prefix = additional_work? ? "[ADDITIONAL] " : ""
    "#{prefix}#{service_type} - #{vehicle.try(:make)} #{vehicle.try(:model)}"
  end

  def to_s
    "#{service_type} (#{safe_date.strftime('%Y-%m-%d')})"
  end

  def urgency_display
    urgency&.humanize || "Normal"
  end

  def owner
    self[:owner] || vehicle&.service_owner
  end

  def owner=(value)
    self[:owner] = value
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
     "Duration", "Status", "Urgency", "Cost", "Notes", "Additional Work"]
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
      notes || "",
      additional_work? ? "Yes" : "No"
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
    next_end = next_start + 7.days
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
      notes: "Automatically scheduled - Next service",
      additional_work: false
    )
  end

  # NEW: Create additional work from this maintenance
  def create_additional_work!(description:, cost: nil, notes: nil)
    child = Maintenance.create!(
      vehicle: vehicle,
      service_type: description,
      status: "Pending",
      start_date: Date.today,
      end_date: Date.today + 7.days,
      date: Date.today,
      cost: cost,
      notes: notes,
      urgency: :high,
      additional_work: true,
      parent_maintenance: self
    )
    
    # Notify finance that additional quotation needed
    notify_finance_for_additional_quotation(child)
    
    child
  end

  # NEW: Mark as cancelled by agency
  def cancel_by_agency!(reason: nil)
    update!(
      cancelled_by_agency: true,
      agency_decision_at: Time.current,
      agency_decision_notes: reason,
      status: "Cancelled"
    )
  end

  private

  def set_defaults
    self.date ||= Date.today if date.nil?
    self.start_date ||= Date.today if start_date.nil?
    self.end_date ||= (Date.today + 7.days) if end_date.nil?
    self.status ||= 'Pending' if status.nil?
    self.urgency ||= :routine if self[:urgency].nil?
    self.assignment_type ||= 'stores' if assignment_type.nil?
    self.category ||= 'General' if category.nil?
    self.owner ||= vehicle&.service_owner if owner.nil?
    self.additional_work ||= false if additional_work.nil?
    self.cancelled_by_agency ||= false if cancelled_by_agency.nil?
  end

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

  def notify_finance_for_additional_quotation(maintenance)
    finance_users = User.where(role: ['finance', 'admin'])
    Notification.create!(
      title: "Additional Work Requires Quotation",
      message: "Additional work '#{maintenance.service_type}' needs a quotation for the agency.",
      link: "/vmcott/finance/quotations/new_for_maintenance/#{maintenance.id}",
      user_id: finance_users.pluck(:id),
      notifiable_type: 'Maintenance',
      notifiable_id: maintenance.id
    )
  end
end