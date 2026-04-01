# app/models/inspection_recommendation.rb
class InspectionRecommendation < ApplicationRecord
  belongs_to :inspection
  belongs_to :suggested_by, class_name: 'User', optional: true
  belongs_to :converted_to_job, class_name: 'InspectionJob', optional: true
  belongs_to :approved_by, class_name: 'User', optional: true
  
  # Status tracking
  enum :status, {
    pending: 'pending',
    approved: 'approved',
    converted: 'converted',
    rejected: 'rejected'
  }, default: :pending
  
  enum :priority, {
    low: 'low',
    normal: 'normal',
    high: 'high',
    critical: 'critical'
  }, default: 'normal'
  
  enum :finding_type, {
    safety: 'safety',
    mechanical: 'mechanical',
    electrical: 'electrical',
    bodywork: 'bodywork',
    maintenance: 'maintenance'
  }
  
  validates :description, presence: true
  validates :finding_type, presence: true
  
  scope :pending_review, -> { where(status: :pending) }
  scope :approved_but_not_converted, -> { where(status: :approved, converted_to_job_id: nil) }
  
  def can_convert_to_job?
    approved? && converted_to_job_id.nil?
  end
  
  def approve!(user)
    update!(
      status: :approved,
      approved_by: user,
      approved_at: Time.current
    )
    
    if suggested_by.present?
      Notification.create!(
        user: suggested_by,
        title: "Recommendation Approved",
        message: "Your recommendation '#{description.truncate(50)}' has been approved.",
        link: "/vmcott/inspector/inspections/#{inspection_id}",
        notification_type: 'success',
        notifiable: self
      )
    end
  end
  
  def reject!(user, reason = nil)
    update!(
      status: :rejected,
      approved_by: user,
      approved_at: Time.current,
      rejection_reason: reason
    )
    
    if suggested_by.present?
      Notification.create!(
        user: suggested_by,
        title: "Recommendation Rejected",
        message: "Your recommendation '#{description.truncate(50)}' was rejected. Reason: #{reason}",
        link: "/vmcott/inspector/inspections/#{inspection_id}",
        notification_type: 'error',
        notifiable: self
      )
    end
  end
  
  def convert_to_job!(user)
    return false unless can_convert_to_job?
    
    job = inspection.inspection_jobs.create!(
      description: description,
      priority: priority,
      estimated_hours: estimated_hours || 1.0,
      status: 'pending_approval',
      created_by: user,
      notes: "From recommendation ##{id} - #{notes}"
    )
    
    update!(
      status: :converted,
      converted_to_job_id: job.id,
      converted_at: Time.current,
      converted_by: user
    )
    
    job
  end
  
  def status_badge_class
    case status
    when 'pending' then 'bg-warning'
    when 'approved' then 'bg-success'
    when 'converted' then 'bg-info'
    when 'rejected' then 'bg-danger'
    else 'bg-secondary'
    end
  end
end