class Vehicle < ApplicationRecord
  # ------------------------------------------------------------
  # Associations
  # ------------------------------------------------------------
  has_many :maintenances, dependent: :destroy
  has_many :trips, dependent: :destroy
  has_many :drivers, through: :trips
  has_many :vehicle_documents, dependent: :destroy

  belongs_to :driver, optional: true

  # ActiveStorage attachments
  has_one_attached :image
  has_one_attached :picture
  has_many_attached :gallery_images

  # ------------------------------------------------------------
  # Trinidad & Tobago license plate rules
  # ------------------------------------------------------------
  TT_PRIMARY_PREFIXES  = %w[P H T G].freeze
  TT_SPECIAL_PREFIXES  = %w[CD RR D R].freeze

  before_validation :normalize_license_plate

  # ------------------------------------------------------------
  # Validations
  # ------------------------------------------------------------
  validates :make, :model, :vehicle_type, :license_plate, :registration_number, presence: true
  validates :chassis_number, :serial_number, :year_of_manufacture, presence: true
  validates :license_plate, :registration_number, uniqueness: true
  validates :service_owner, presence: true, inclusion: { in: ["PTSC", "Police", "Fire Service"] }

  validates :license_plate, format: {
    with: /\A([A-Z]{3}|CD|RR|D|R)-\d{1,4}\z/,
    message: "must follow Trinidad format (ABC-1234)"
  }

  # ------------------------------------------------------------
  # Maintenance helpers
  # ------------------------------------------------------------
  def overdue_maintenances
    maintenances.overdue
  end

  def upcoming_maintenances
    maintenances.upcoming
  end

  def has_overdue_maintenance?
    overdue_maintenances.exists?
  end

  # ------------------------------------------------------------
  # Gantt Chart Helpers
  # ------------------------------------------------------------
  def current_driver_name
    driver&.name || 'Unassigned'
  end

  def gantt_tasks(time_period_days: 90)
    today = Date.today
    
    # Group maintenances by time periods
    maintenances_with_dates = maintenances.where.not(start_date: nil).order(:start_date)
    return [] if maintenances_with_dates.empty?
    
    # Define time periods
    time_periods = {
      this_week: { name: "📅 This Week", start: today, end: today + 6.days },
      next_week: { name: "📅 Next Week", start: today + 7.days, end: today + 13.days },
      this_month: { name: "📅 This Month", start: today + 14.days, end: today.end_of_month },
      future: { name: "📅 Future", start: today.end_of_month + 1.day, end: today + time_period_days.days }
    }
    
    gantt_data = []
    
    # TIER 2: Time-based folders
    time_periods.each do |period_key, period|
      # Find maintenances in this time period
      period_maintenances = maintenances_with_dates.select do |m|
        m.start_date && m.start_date.between?(period[:start], period[:end])
      end
      
      next if period_maintenances.empty?
      
      folder_start = period_maintenances.map(&:start_date).min
      folder_end = period_maintenances.map { |m| m.gantt_end_date }.max
      
      folder_data = {
        name: period[:name],
        start: folder_start,
        end: folder_end,
        type: 'folder',
        period_key: period_key,
        maintenances: period_maintenances
      }
      
      gantt_data << folder_data
    end
    
    gantt_data
  end

  # ------------------------------------------------------------
  # Display helpers
  # ------------------------------------------------------------
  def display_name
    "#{make} - #{license_plate}"
  end

  def full_display_name
    "#{make} #{model} (#{registration_number})"
  end

  # ------------------------------------------------------------
  # License plate normalization
  # ------------------------------------------------------------
  def normalize_license_plate
    return if license_plate.blank?

    plate = license_plate.to_s.strip.upcase.gsub(/\s+/, "").gsub(/[^A-Z0-9]/, "")
    prefix  = plate[/\A[A-Z]+/]
    numbers = plate[/\d+/]
    return if prefix.blank? || numbers.blank?

    prefix = prefix[0,3] if prefix.length > 3
    self.license_plate = "#{prefix}-#{numbers}"
  end

  # ------------------------------------------------------------
  # Search scope
  # ------------------------------------------------------------
  scope :search, ->(query) {
    return all if query.blank?
    where("make ILIKE :q OR model ILIKE :q OR license_plate ILIKE :q", q: "%#{query}%")
  }

  # ------------------------------------------------------------
  # Usage analytics helper
  # ------------------------------------------------------------
  def usage_stats(from:, to:)
    trips_in_range = trips.where(start_time: from.beginning_of_day..to.end_of_day)

    # Use pluck + sum to avoid calling method on ActiveRecord relation
    distance_sum = trips_in_range.sum(:distance_km).to_f
    hours_sum    = trips_in_range.pluck(:id).sum { |id| Trip.find(id).duration_hours.to_f }
    trip_count   = trips_in_range.count

    total_days = [(to - from + 1).to_i, 1].max # prevent division by zero
    utilization = ((hours_sum / (total_days * 24.0)) * 100).round(1)

    {
      name: "#{make} #{model} (#{registration_number || 'N/A'})",
      distance_km: distance_sum,
      hours_plied: hours_sum,
      trip_count: trip_count,
      utilization_percent: utilization
    }
  end
end