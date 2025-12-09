class Trip < ApplicationRecord
  belongs_to :vehicle
  belongs_to :driver, class_name: "User", optional: true

  # Validations
  validates :start_time, :end_time, presence: true
  validate :start_time_in_past
  validate :end_time_in_future
  validate :end_after_start

  # Scope for trips between two dates
  scope :between, ->(from, to) {
    where("start_time >= ? AND end_time <= ?", from.beginning_of_day, to.end_of_day)
  }

  # Duration in seconds
  def duration_seconds
    (end_time - start_time).to_i
  end

  # Duration in hours
  def duration_hours
    duration_seconds / 3600.0
  end

  private

  # Ensure start_time is not in the future
  def start_time_in_past
    if start_time.present? && start_time > Time.current
      errors.add(:start_time, "cannot be in the future")
    end
  end

  # Ensure end_time is not in the past (or optionally skip in seeds)
  def end_time_in_future
    if end_time.present? && end_time < Time.current
      errors.add(:end_time, "cannot be in the past")
    end
  end

  # Ensure end_time is after start_time
  def end_after_start
    if start_time.present? && end_time.present? && end_time <= start_time
      errors.add(:end_time, "must be after start_time")
    end
  end
end
