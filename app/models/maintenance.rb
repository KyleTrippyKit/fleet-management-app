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

  # =====================================================
  # Validations
  # =====================================================
  validates :status, inclusion: { in: STATUSES }
  validates :assignment_type, inclusion: { in: ASSIGNMENT_TYPES }, presence: true
  validates :urgency, inclusion: { in: URGENCIES }, presence: true
  validates :service_provider, presence: true, unless: :completed?

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

  # =====================================================
  # Status Helpers
  # =====================================================
  def completed?
    status == "Completed"
  end

  def pending?
    status == "Pending"
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

  # Label for dropdown urgency (Routine / Scheduled / Emergency)
  def urgency_dropdown_label
    case urgency
    when "routine"   then "Routine"
    when "scheduled" then "Scheduled"
    when "emergency" then "Emergency"
    else "N/A"
    end
  end

  # Badge class for dropdown urgency
  def urgency_dropdown_badge_class
    case urgency
    when "routine"   then "bg-primary text-white"
    when "scheduled" then "bg-warning text-dark"
    when "emergency" then "bg-danger text-white"
    else "bg-secondary"
    end
  end

  # =====================================================
  # Next Due & Dashboard Logic
  # =====================================================
  def urgency_level
    return :completed if completed?
    return :na if next_due_date.blank?

    days = (next_due_date - Date.today).to_i

    return :overdue if days < 0
    return :soon if days <= 14

    :ok
  end

  def urgency_label
    case urgency_level
    when :completed then "Completed"
    when :overdue   then "Overdue #{days_overdue}d"
    when :soon      then "Due Soon"
    when :na        then "N/A"
    else "OK"
    end
  end

  def urgency_badge_class
    case urgency_level
    when :overdue   then "bg-danger"
    when :soon      then "bg-warning text-dark"
    when :completed then "bg-success"
    when :na        then "bg-secondary"
    else "bg-success"
    end
  end

  def days_overdue
    return 0 unless next_due_date
    (Date.today - next_due_date).to_i
  end

  # =====================================================
  # Reminder Helpers
  # =====================================================
  def reminder_status
    return "Completed" if completed?
    return "Overdue" if next_due_date.present? && next_due_date < Date.today
    return "Due Today" if next_due_date == Date.today
    return "Upcoming" if next_due_date.present? && next_due_date <= 30.days.from_now

    "OK"
  end

  # =====================================================
  # Mileage Helpers
  # =====================================================
  def mileage_until_next_service(interval = 5_000)
    return nil unless mileage && vehicle&.mileage

    next_service_mileage = mileage + interval
    next_service_mileage - vehicle.mileage
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
