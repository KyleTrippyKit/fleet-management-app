# app/models/route.rb
class Route < ApplicationRecord
  belongs_to :agency
  has_many :fare_rules, foreign_key: :route_code, primary_key: :route_code
  
  # Validations
  validates :route_code, presence: true, uniqueness: { scope: :agency_id }
  validates :name, presence: true
  validates :distance_km, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :estimated_duration_minutes, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  
  # Scopes
  scope :active, -> { where(is_active: true) }
  scope :by_agency, ->(agency) { where(agency: agency) }
  scope :search, ->(query) {
    where("route_code ILIKE ? OR name ILIKE ? OR start_point ILIKE ? OR end_point ILIKE ?",
          "%#{query}%", "%#{query}%", "%#{query}%", "%#{query}%")
  }
  
  # Callbacks
  before_save :normalize_route_code
  before_save :set_default_stops
  
  # Instance methods
  def display_name
    "#{route_code}: #{name}"
  end
  
  def full_route_name
    if start_point.present? && end_point.present?
      "#{name} (#{start_point} to #{end_point})"
    else
      name
    end
  end
  
  def formatted_distance
    return "N/A" if distance_km.blank?
    "#{'%.1f' % distance_km} km"
  end
  
  def formatted_duration
    return "N/A" if estimated_duration_minutes.blank?
    hours = estimated_duration_minutes / 60
    minutes = estimated_duration_minutes % 60
    if hours > 0
      "#{hours}h #{minutes}m"
    else
      "#{minutes} mins"
    end
  end
  
  def stops_array
    stops || []
  end
  
  def display_stops
    return "No stops defined" if stops.blank?
    stops.join(' → ')
  end
  
  def current_fare_rules
    fare_rules.active.where(
      "(effective_from IS NULL OR effective_from <= ?) AND (effective_to IS NULL OR effective_to >= ?)",
      Date.current, Date.current
    )
  end
  
  def fare_for_class(fare_class)
    fare_rules.active
      .where(fare_class: fare_class)
      .where("(effective_from IS NULL OR effective_from <= ?) AND (effective_to IS NULL OR effective_to >= ?)",
            Date.current, Date.current)
      .order(effective_from: :desc)
      .first
  end
  
  def fare_amount_for_class(fare_class)
    fare = fare_for_class(fare_class)
    fare&.amount_for_class(fare_class) || 0.0
  end
  
  def fare_classes
    fare_rules.active.pluck(:fare_class).uniq.sort
  end
  
  def route_summary
    {
      id: id,
      code: route_code,
      name: name,
      full_name: full_route_name,
      distance: formatted_distance,
      duration: formatted_duration,
      stops_count: stops_array.count,
      fare_classes: fare_classes,
      is_active: is_active?
    }
  end
  
  def deactivate!
    update!(is_active: false)
  end
  
  def activate!
    update!(is_active: true)
  end
  
  private
  
  def normalize_route_code
    self.route_code = route_code.upcase.strip if route_code.present?
  end
  
  def set_default_stops
    self.stops = [] if stops.nil?
  end
end