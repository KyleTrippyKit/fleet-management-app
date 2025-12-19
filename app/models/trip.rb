class Trip < ApplicationRecord
  # ========================
  # Associations
  # ========================
  belongs_to :vehicle
  belongs_to :driver, optional: true

  # ========================
  # Validations
  # ========================
  validates :start_time, presence: true
  validates :end_time, presence: true, unless: :ongoing?

  validate :start_time_not_in_future
  validate :end_time_after_start
  validate :end_time_not_in_future, unless: :ongoing?

  # ========================
  # Scopes
  # ========================
  scope :between, ->(from, to) {
    where("start_time >= ? AND (end_time <= ? OR end_time IS NULL)",
          from.beginning_of_day,
          to.end_of_day)
  }

  scope :ongoing, -> { where(end_time: nil) }
  scope :completed, -> { where.not(end_time: nil) }

  # ========================
  # Instance Methods
  # ========================

  def ongoing?
    end_time.nil?
  end

  # Returns trip duration in seconds
  def duration_seconds
    return 0 if ongoing?
    (end_time - start_time).to_i
  end

  # Returns trip duration in hours
  def duration_hours
    return 0 if ongoing?
    duration_seconds / 3600.0
  end

  # Returns distance in km; defaults to 0 if nil
  def distance_km
    self[:distance_km].to_f
  end

  # ========================
  # Display helper
  # ========================
  def display_name
    "#{vehicle.display_name} - Trip ##{id}"
  end

  private

  # ========================
  # Custom Validators
  # ========================
  def start_time_not_in_future
    return if start_time.blank?
    errors.add(:start_time, "cannot be in the future") if start_time > Time.current
  end

  def end_time_after_start
    return if start_time.blank? || end_time.blank?
    errors.add(:end_time, "must be after start time") if end_time <= start_time
  end

  def end_time_not_in_future
    return if end_time.blank?
    errors.add(:end_time, "cannot be in the future") if end_time > Time.current
  end
end
