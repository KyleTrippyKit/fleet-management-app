class VehicleStatus < ApplicationRecord
  belongs_to :vehicle
  belongs_to :created_by, class_name: 'User', optional: true
  
  # The status flow you described
  STATUSES = [
    'pending_reception',      # Agency submitted, not yet at VMCOTT
    'vehicle_received',       # Receptionist scanned QR/entered plate
    'pending_inspection',     # Waiting for inspector
    'inspection_in_progress', # Inspector working on it
    'inspection_complete',    # Inspector finished, jobs created
    'awaiting_parts',         # Parts needed, waiting for coordinator
    'parts_ordered',          # RFQs sent, waiting for vendors
    'parts_received',         # Parts arrived
    'ready_for_repair',       # Parts ready, waiting for mechanic
    'repair_in_progress',     # Mechanic working
    'repair_complete',        # Mechanic finished, waiting for QC
    'qc_pending',             # Waiting for inspector QC
    'qc_in_progress',         # Inspector doing QC
    'qc_passed',              # QC passed, ready for pickup
    'qc_failed',              # QC failed, needs rework
    'ready_for_pickup',       # Vehicle ready
    'completed'               # Vehicle returned to agency
  ].freeze
  
  # Status categories for dashboard
  CATEGORIES = {
    'pending_reception' => 'pending',
    'vehicle_received' => 'active',
    'pending_inspection' => 'active',
    'inspection_in_progress' => 'active',
    'inspection_complete' => 'active',
    'awaiting_parts' => 'blocked',
    'parts_ordered' => 'blocked',
    'parts_received' => 'active',
    'ready_for_repair' => 'active',
    'repair_in_progress' => 'active',
    'repair_complete' => 'active',
    'qc_pending' => 'active',
    'qc_in_progress' => 'active',
    'qc_passed' => 'active',
    'qc_failed' => 'blocked',
    'ready_for_pickup' => 'completed',
    'completed' => 'completed'
  }.freeze
  
  # Agency visibility - which statuses agency can see
  AGENCY_VISIBLE_STATUSES = [
    'pending_reception',
    'vehicle_received',
    'inspection_complete',
    'awaiting_parts',
    'parts_ordered',
    'repair_in_progress',
    'ready_for_pickup',
    'completed'
  ].freeze
  
  validates :status, presence: true, inclusion: { in: STATUSES }
  
  scope :current, -> { where(current: true) }
  scope :for_vehicle, ->(vehicle_id) { where(vehicle_id: vehicle_id).order(created_at: :desc) }
  scope :visible_to_agency, -> { where(status: AGENCY_VISIBLE_STATUSES) }
  
  after_create :set_as_current, if: :current?
  after_create :notify_agency_if_visible
  
  def status_category
    CATEGORIES[status] || 'other'
  end
  
  def status_display
    status.titleize
  end
  
  def status_badge_color
    case status_category
    when 'pending' then 'secondary'
    when 'active' then 'primary'
    when 'blocked' then 'warning'
    when 'completed' then 'success'
    else 'info'
    end
  end
  
  def visible_to_agency?
    AGENCY_VISIBLE_STATUSES.include?(status)
  end
  
  private
  
  def set_as_current
    vehicle.vehicle_statuses.where(current: true).update_all(current: false)
    update_column(:current, true)
    
    # Safely update vehicle's current_status if the column exists
    if vehicle.respond_to?(:current_status) && vehicle.has_attribute?('current_status')
      vehicle.update_column(:current_status, status)
    end
  end
  
  def notify_agency_if_visible
    return unless visible_to_agency?
    
    # Get license plate safely
    license_plate = vehicle.respond_to?(:license_plate) ? vehicle.license_plate : "Vehicle #{vehicle.id}"
    
    # Ensure the channel is loaded
    begin
        # Try to broadcast to Action Cable
        VehicleStatusChannel.broadcast_to(
        vehicle,
        {
            vehicle_id: vehicle.id,
            status: status,
            status_display: status_display,
            status_badge_color: status_badge_color,
            notes: notes,
            timestamp: Time.current,
            license_plate: license_plate,
            message: "Vehicle #{license_plate} is now #{status_display}"
        }
        )
        Rails.logger.info "✅ Broadcasted vehicle #{vehicle.id} status: #{status}"
    rescue => e
        Rails.logger.error "❌ Failed to broadcast vehicle status: #{e.message}"
    end
    
    # Also create a notification if you have that model
    if defined?(Notification) && vehicle.respond_to?(:agency_id)
        begin
        Notification.create!(
            title: "Vehicle Status Update",
            message: "Vehicle #{license_plate} is now #{status_display}",
            link: Rails.application.routes.url_helpers.vehicle_path(vehicle),
            recipient_type: 'agency',
            agency_id: vehicle.agency_id
        )
        rescue => e
        Rails.logger.error "Failed to create notification: #{e.message}"
        end
    end
  end
end