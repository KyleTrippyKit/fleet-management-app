class Vehicle < ApplicationRecord
  # ------------------------------------------------------------
  # Associations
  # ------------------------------------------------------------
  belongs_to :driver, optional: true   # One driver per vehicle

  has_many :maintenances, dependent: :destroy
  has_many :trips, dependent: :destroy
  has_many :vehicle_documents, dependent: :destroy

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
  # Scopes for filtering
  # ------------------------------------------------------------
  scope :by_service_owner, ->(owner) { where(service_owner: owner) if owner.present? }
  scope :by_type, ->(type) { where(vehicle_type: type) if type.present? }
  scope :with_active_maintenance, -> { joins(:maintenances).where(maintenances: { status: 'Pending' }).distinct }

  # ------------------------------------------------------------
  # Maintenance helpers
  # ------------------------------------------------------------
  def overdue_maintenances
    maintenances.overdue
  end

  def upcoming_maintenances
    maintenances.upcoming
  end

  def active_maintenances
    maintenances.active
  end

  def completed_maintenances
    maintenances.completed
  end

  def has_overdue_maintenance?
    overdue_maintenances.exists?
  end

  def has_active_maintenance?
    active_maintenances.exists?
  end

  def next_maintenance_date
    maintenances.pending.where.not(start_date: nil).minimum(:start_date)
  end

  def maintenance_status_summary
    {
      total: maintenances.count,
      pending: maintenances.pending.count,
      completed: maintenances.completed.count,
      overdue: overdue_maintenances.count,
      active: active_maintenances.count,
      upcoming: upcoming_maintenances.count
    }
  end

  # ------------------------------------------------------------
  # Driver helpers
  # ------------------------------------------------------------
  def current_driver_name
    driver&.name || 'Unassigned'
  end

  # ------------------------------------------------------------
  # Gantt Chart / Timeline Helpers
  # ------------------------------------------------------------
  def gantt_task_data(maintenances_for_vehicle = nil)
    vehicle_maintenances = maintenances_for_vehicle || maintenances
    dated_maintenances = vehicle_maintenances.select { |m| m.start_date && m.end_date }
    return nil if dated_maintenances.empty?

    start_dates = dated_maintenances.map(&:start_date)
    end_dates   = dated_maintenances.map(&:end_date)
    return nil if start_dates.empty? || end_dates.empty?

    {
      id: "vehicle_#{id}",
      name: "#{make} #{model} (#{registration_number})",
      start: start_dates.min.to_s,
      end: end_dates.max.to_s,
      parent: "0",
      type: 'vehicle',
      color: '#6c757d',
      details: {
        service_owner: service_owner,
        registration_number: registration_number,
        current_driver: current_driver_name,
        license_plate: license_plate,
        vehicle_type: vehicle_type,
        maintenance_count: dated_maintenances.count
      }
    }
  end

  def gantt_maintenance_tasks
    maintenances.where.not(start_date: nil).where.not(end_date: nil).map(&:gantt_task_data).compact
  end

  def gantt_color_for_status
    if has_overdue_maintenance?
      '#dc3545'
    elsif has_active_maintenance?
      '#0dcaf0'
    elsif upcoming_maintenances.exists?
      '#ffc107'
    else
      '#6c757d'
    end
  end

  def timeline_events(start_date: Date.today - 30.days, end_date: Date.today + 90.days)
    events = []

    maintenances.where('start_date IS NOT NULL AND start_date <= ? AND end_date >= ?', 
                      end_date, start_date).each do |m|
      events << {
        id: "maintenance_#{m.id}",
        title: m.service_type,
        start: m.start_date,
        end: m.end_date,
        color: m.gantt_bar_color,
        type: 'maintenance',
        data: m
      }
    end

    if registration_expiry_date.present?
      events << {
        id: "registration_#{id}",
        title: "Registration Renewal",
        start: registration_expiry_date - 30.days,
        end: registration_expiry_date,
        color: '#6610f2',
        type: 'registration'
      }
    end

    events.sort_by { |e| e[:start] }
  end

  # ------------------------------------------------------------
  # Display helpers
  # ------------------------------------------------------------
  def display_name
    "#{make} #{model} - #{license_plate}"
  end

  def full_display_name
    "#{make} #{model} (#{registration_number})"
  end

  def display_with_owner
    "#{make} #{model} (#{registration_number}) - #{service_owner}"
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
    where("make ILIKE :q OR model ILIKE :q OR license_plate ILIKE :q OR registration_number ILIKE :q", q: "%#{query}%")
  }

  # ------------------------------------------------------------
  # Usage analytics helper
  # ------------------------------------------------------------
  def usage_stats(from:, to:)
    trips_in_range = trips.where(start_time: from.beginning_of_day..to.end_of_day)
    distance_sum = trips_in_range.sum(:distance_km).to_f
    hours_sum    = trips_in_range.pluck(:id).sum { |id| Trip.find(id).duration_hours.to_f }
    trip_count   = trips_in_range.count

    total_days = [(to - from + 1).to_i, 1].max
    utilization = ((hours_sum / (total_days * 24.0)) * 100).round(1)

    {
      name: "#{make} #{model} (#{registration_number || 'N/A'})",
      distance_km: distance_sum,
      hours_plied: hours_sum,
      trip_count: trip_count,
      utilization_percent: utilization,
      maintenance_status: maintenance_status_summary
    }
  end

  # ------------------------------------------------------------
  # Image helpers
  # ------------------------------------------------------------
  include ImageOptimizable

  def primary_image_url
    if image.attached?
      Rails.application.routes.url_helpers.url_for(image)
    elsif picture.attached?
      Rails.application.routes.url_helpers.url_for(picture)
    else
      nil
    end
  end

  def gallery_image_urls
    gallery_images.attached? ? gallery_images.map { |img| Rails.application.routes.url_helpers.url_for(img) } : []
  end

  # ------------------------------------------------------------
  # Validation status for UI
  # ------------------------------------------------------------
  def validation_status
    issues = []
    issues << "No maintenances scheduled" if maintenances.empty?
    issues << "No driver assigned" if driver.blank?
    issues << "Overdue maintenance" if has_overdue_maintenance?

    if issues.empty?
      { status: 'good', message: 'All good' }
    elsif issues.include?("Overdue maintenance")
      { status: 'danger', message: 'Overdue maintenance' }
    else
      { status: 'warning', message: issues.first }
    end
  end
end
