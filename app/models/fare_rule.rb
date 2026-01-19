# app/models/fare_rule.rb
class FareRule < ApplicationRecord
  belongs_to :agency
  belongs_to :route, foreign_key: :route_code, primary_key: :route_code, optional: true
  
  # Constants for fare classes
  FARE_CLASSES = {
    adult: 'adult',
    child: 'child',
    student: 'student',
    senior: 'senior',
    concession: 'concession',
    standard: 'standard',
    express: 'express',
    luxury: 'luxury'
  }.freeze
  
  # Validations
  validates :agency, presence: true
  validates :route_code, presence: true
  validates :fare_class, presence: true, inclusion: { in: FARE_CLASSES.values }
  validates :amount, presence: true, numericality: { greater_than: 0 }
  validates :child_amount, numericality: { greater_than: 0 }, allow_nil: true
  validates :student_amount, numericality: { greater_than: 0 }, allow_nil: true
  validates :senior_amount, numericality: { greater_than: 0 }, allow_nil: true
  
  # Validate effective dates
  validate :effective_dates_validity
  
  # Scopes
  scope :active, -> { where(is_active: true) }
  scope :current, -> { 
    active.where("(effective_from IS NULL OR effective_from <= ?) AND (effective_to IS NULL OR effective_to >= ?)",
                Date.current, Date.current)
  }
  scope :for_agency, ->(agency) { where(agency: agency) }
  scope :for_route, ->(route_code) { where(route_code: route_code) }
  scope :for_fare_class, ->(fare_class) { where(fare_class: fare_class) }
  scope :effective_on, ->(date) {
    where("(effective_from IS NULL OR effective_from <= ?) AND (effective_to IS NULL OR effective_to >= ?)",
          date, date)
  }
  
  # Callbacks
  before_validation :normalize_fare_class
  before_save :set_default_amounts
  
  # Class methods
  def self.find_current_fare(agency, route_code, fare_class)
    for_agency(agency)
      .for_route(route_code)
      .for_fare_class(fare_class)
      .current
      .order(effective_from: :desc)
      .first
  end
  
  def self.bulk_update!(agency, route_code, fare_data)
    transaction do
      fare_data.each do |fare_class, amount|
        find_or_initialize_by(
          agency: agency,
          route_code: route_code,
          fare_class: fare_class,
          effective_from: Date.current
        ).update!(
          amount: amount,
          is_active: true
        )
      end
    end
  end
  
  # Instance methods
  def display_name
    "#{route_code} - #{fare_class.titleize}: TT$#{'%.2f' % amount}"
  end
  
  def fare_class_title
    fare_class.titleize
  end
  
  def formatted_amount
    "TT$#{'%.2f' % amount}"
  end
  
  def amount_for_class(fare_class_type)
    case fare_class_type.to_s
    when 'child'
      child_amount || amount * 0.5
    when 'student'
      student_amount || amount * 0.7
    when 'senior'
      senior_amount || amount * 0.6
    else
      amount
    end
  end
  
  def formatted_amount_for_class(fare_class_type)
    "TT$#{'%.2f' % amount_for_class(fare_class_type)}"
  end
  
  def effective_period
    if effective_from && effective_to
      "#{effective_from.to_date} to #{effective_to.to_date}"
    elsif effective_from
      "From #{effective_from.to_date}"
    elsif effective_to
      "Until #{effective_to.to_date}"
    else
      "Always active"
    end
  end
  
  def is_current?
    return false unless is_active?
    return true unless effective_from || effective_to
    
    today = Date.current
    (!effective_from || effective_from <= today) && (!effective_to || effective_to >= today)
  end
  
  def deactivate!
    update!(is_active: false)
  end
  
  def activate!
    update!(is_active: true)
  end
  
  def duplicate_for_new_period(start_date, end_date = nil)
    dup.tap do |new_rule|
      new_rule.effective_from = start_date
      new_rule.effective_to = end_date
      new_rule.is_active = true
      new_rule.save!
    end
  end
  
  def fare_summary
    {
      id: id,
      route_code: route_code,
      route_name: route&.name,
      fare_class: fare_class,
      fare_class_title: fare_class_title,
      amount: amount,
      formatted_amount: formatted_amount,
      child_amount: child_amount,
      student_amount: student_amount,
      senior_amount: senior_amount,
      effective_period: effective_period,
      is_current: is_current?,
      is_active: is_active?,
      notes: notes
    }
  end
  
  private
  
  def normalize_fare_class
    self.fare_class = fare_class.downcase.strip if fare_class.present?
  end
  
  def set_default_amounts
    # Set default discounted amounts if not provided
    self.child_amount ||= amount * 0.5 if amount.present? && fare_class == 'adult'
    self.student_amount ||= amount * 0.7 if amount.present? && fare_class == 'adult'
    self.senior_amount ||= amount * 0.6 if amount.present? && fare_class == 'adult'
  end
  
  def effective_dates_validity
    if effective_from && effective_to && effective_from > effective_to
      errors.add(:effective_to, "must be after effective from date")
    end
  end
end