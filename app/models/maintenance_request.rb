class MaintenanceRequest < ApplicationRecord
  belongs_to :vehicle
  belongs_to :requesting_agency, class_name: 'Agency'
  belongs_to :processing_agency, class_name: 'Agency', optional: true
  
  enum status: {
    pending: 'pending',
    approved: 'approved',
    in_progress: 'in_progress',
    completed: 'completed',
    rejected: 'rejected'
  }
  
  enum priority: {
    low: 'low',
    medium: 'medium',
    high: 'high',
    emergency: 'emergency'
  }
  
  scope :overdue, -> { where('requested_date < ?', 7.days.ago).where(status: ['pending', 'approved']) }
  scope :for_agency, ->(agency) { where(requesting_agency_id: agency.id) }
end