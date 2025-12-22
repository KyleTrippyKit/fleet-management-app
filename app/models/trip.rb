class Trip < ApplicationRecord
  # ========================
  # Associations
  # ========================
  belongs_to :vehicle
  belongs_to :driver, class_name: "User", optional: true

  # ========================
  # Validations
  # ========================
  validates :start_time, presence: true
  validates :end_time, presence: true, unless: :ongoing?
  validates :distance_km, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true

  validate :start_time_not_in_future
  validate :end_time_after_start
  validate :end_time_not_in_future, unless: :ongoing?

  # ========================
  # Scopes
  # ========================
  scope :between, ->(from, to) {
    where(
      "start_time >= ? AND (end_time <= ? OR end_time IS NULL)",
      from.beginning_of_day,
      to.end_of_day
    )
  }

  scope :ongoing, -> { where(end_time: nil) }
  scope :completed, -> { where.not(end_time: nil) }

  # For vehicles controller analytics
  scope :in_date_range, ->(from, to) {
    where(start_time: from.beginning_of_day..to.end_of_day)
  }

  # ========================
  # Instance Methods
  # ========================

  def ongoing?
    end_time.nil?
  end

  def completed?
    !ongoing?
  end

  # Returns trip status
  def status
    ongoing? ? "In Progress" : "Completed"
  end

  # Returns CSS class for status badge
  def status_class
    ongoing? ? "warning" : "success"
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

  # Returns formatted duration
  def formatted_duration
    return "Ongoing" if ongoing?

    hours = duration_hours.floor
    minutes = ((duration_hours - hours) * 60).round

    if hours.positive?
      "#{hours}h #{minutes}m"
    else
      "#{minutes}m"
    end
  end

  # Returns distance in km; defaults to 0 if nil
  def distance_km
    self[:distance_km].to_f
  end

  # Returns formatted distance
  def formatted_distance
    "#{distance_km.round(2)} km"
  end

  # ========================
  # Display helpers
  # ========================
  def display_name
    "#{vehicle&.display_name || 'Vehicle'} - Trip ##{id}"
  end

  # For dropdowns and selects
  def to_s
    "Trip ##{id} - #{start_time.strftime('%Y-%m-%d %H:%M')}"
  end

  # ========================
  # Class Methods
  # ========================

  # Calculate total distance for a set of trips
  def self.total_distance(trips)
    trips.sum(:distance_km).to_f.round(2)
  end

  # Calculate total hours for a set of trips
  def self.total_hours(trips)
    trips.sum(:duration_hours).to_f.round(2)
  end

  # Calculate average distance per trip
  def self.average_distance(trips)
    count = trips.count
    count.positive? ? (total_distance(trips) / count).round(2) : 0
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
