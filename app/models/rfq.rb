class Rfq < ApplicationRecord
  # Associations
  belongs_to :requesting_agency, class_name: 'Agency'
  belongs_to :processing_agency, class_name: 'Agency', optional: true
  belongs_to :vehicle, optional: true
  belongs_to :maintenance_request, optional: true
  belongs_to :converted_to_quotation, class_name: 'Quotation', optional: true
  
  has_many :rfq_line_items, dependent: :destroy
  
  # Validations
  validates :rfq_number, presence: true, uniqueness: true
  validates :request_date, presence: true
  validates :requesting_agency_id, presence: true
  
  # FIXED: Updated enum to include 'converted' status
  enum :status, {
    draft: 'draft',
    submitted: 'submitted',
    under_review: 'under_review',
    quoted: 'quoted',
    converted: 'converted',
    rejected: 'rejected',
    accepted: 'accepted'
  }, default: :draft
  
  # FIXED: Renamed scopes to avoid conflict with enum methods
  scope :status_draft, -> { where(status: 'draft') }
  scope :status_submitted, -> { where(status: 'submitted') }
  scope :status_under_review, -> { where(status: 'under_review') }
  scope :status_quoted, -> { where(status: 'quoted') }
  scope :status_converted, -> { where(status: 'converted') }
  scope :status_rejected, -> { where(status: 'rejected') }
  scope :status_accepted, -> { where(status: 'accepted') }
  
  # NEW: Scopes for filtering
  scope :by_status, ->(status) { where(status: status) if status.present? }
  scope :by_vehicle, ->(vehicle_id) { where(vehicle_id: vehicle_id) if vehicle_id.present? }
  scope :by_agency, ->(agency_id) { where(requesting_agency_id: agency_id) if agency_id.present? }
  scope :search, ->(query) { 
    return all if query.blank?
    where('rfq_number ILIKE :q OR description ILIKE :q', q: "%#{query}%")
  }
  scope :date_range, ->(start_date, end_date) { 
    return all if start_date.blank? || end_date.blank?
    where(request_date: Date.parse(start_date)..Date.parse(end_date))
  }
  
  # Callbacks for email notifications
  after_update :send_status_notification, if: :saved_change_to_status?
  after_create :send_creation_notification
  
  # Callback
  before_validation :generate_rfq_number, on: :create
  
  def submit_to_vmcott!
    update(status: 'submitted')
  end
  
  # NEW: Status badge color for UI
  def status_badge_color
    case status
    when 'draft' then 'secondary'
    when 'submitted' then 'info'
    when 'under_review' then 'warning'
    when 'quoted' then 'primary'
    when 'converted' then 'success'
    when 'accepted' then 'success'
    when 'rejected' then 'danger'
    else 'secondary'
    end
  end
  
  # NEW: PDF filename
  def pdf_filename
    "#{rfq_number.gsub(/[^a-zA-Z0-9]/, '_')}.pdf"
  end
  
  # NEW: Total items count
  def total_items
    rfq_line_items.sum(:quantity)
  end
  
  # NEW: Check if response is overdue
  def response_overdue?
    return false if response_due_date.blank?
    response_due_date < Date.today && ['submitted', 'under_review'].include?(status)
  end
  
  private
  
  def generate_rfq_number
    return if rfq_number.present?
    
    date_part = Time.now.strftime('%Y%m%d')
    random_part = SecureRandom.hex(3).upcase
    self.rfq_number = "RFQ-#{date_part}-#{random_part}"
  end
  
  # NEW: Email notification methods
  def send_status_notification
    # Don't send for draft updates
    return if status_previously_was == 'draft' && status == 'draft'
    
    RfqMailer.status_changed(self).deliver_later
  end
  
  def send_creation_notification
    # Only send for non-draft or when submitted immediately
    return if draft? && !saved_change_to_status? 
    RfqMailer.rfq_created(self).deliver_later
  end
end