# app/models/finding.rb
class Finding < ApplicationRecord
  belongs_to :inspection
  belongs_to :inspection_job, optional: true
  belongs_to :created_by, class_name: 'User', optional: true
  belongs_to :job, class_name: 'InspectionJob', optional: true
  belongs_to :work_order, optional: true
  belongs_to :approved_by, class_name: 'User', optional: true

  validates :finding_type, presence: true
  validates :description, presence: true
  validates :severity, inclusion: { in: ['critical', 'major', 'minor'] }
  validates :priority, inclusion: { in: ['low', 'normal', 'high', 'critical'] }, allow_nil: true

  attribute :job_created, :boolean, default: false
  attribute :priority, :string, default: 'normal'

  # Updated finding types for 14-step workflow
  enum :finding_type, {
    initial: 'initial',      # From initial inspection
    mechanic: 'mechanic',    # From mechanic during review
    final: 'final',          # From final inspection
    additional: 'additional' # NEW: From mechanic during work
  }

  enum :status, {
    pending: 'pending',
    approved: 'approved',
    rejected: 'rejected',
    in_progress: 'in_progress',
    completed: 'completed'
  }, default: :pending

  scope :blocking, -> { where(blocking: true) }
  scope :unapproved, -> { where(client_approved: false) }
  scope :pending_job_creation, -> { where(job_created: false) }
  scope :pending_review, -> { where(status: :pending) }
  scope :approved_findings, -> { where(status: :approved) }
  scope :critical, -> { where(severity: 'critical') }
  scope :for_inspection, ->(inspection_id) { where(inspection_id: inspection_id) }
  scope :for_job, ->(job_id) { where(inspection_job_id: job_id) }

  after_create :notify_supervisor_if_blocking

  # =====================================================
  # APPROVAL METHODS
  # =====================================================
  
  def approve!(user)
    update!(
      status: :approved,
      approved_by: user,
      approved_at: Time.current
    )
    
    # Create a job from this finding if needed
    if block_until_resolved? && !job_created
      create_job_from_finding(user)
    end
    
    Notification.create!(
      user: created_by,
      title: "Finding Approved",
      message: "Your finding '#{description}' has been approved.",
      link: "/vmcott/workshop_supervisor/findings/#{id}",
      notification_type: 'success',
      notifiable: self
    )
  end
  
  def reject!(user, reason = nil)
    update!(
      status: :rejected,
      rejected_by: user,
      rejected_at: Time.current,
      rejection_reason: reason
    )
    
    Notification.create!(
      user: created_by,
      title: "Finding Rejected",
      message: "Your finding '#{description}' was rejected. Reason: #{reason}",
      link: "/vmcott/workshop_supervisor/findings/#{id}",
      notification_type: 'danger',
      notifiable: self
    )
  end
  
  def create_job_from_finding(user)
    job = inspection.inspection_jobs.create!(
      description: description,
      estimated_hours: 1.0,  # Default, can be updated by supervisor
      priority: severity == 'critical' ? 'high' : 'normal',
      status: 'pending_approval',
      recommendation_source: 'finding',
      created_by: user
    )
    
    update!(
      job_id: job.id,
      inspection_job_id: job.id,
      job_created: true
    )
  end
  
  def block_until_resolved?
    blocking && status != 'completed'
  end

  def severity_badge_class
    case severity
    when 'critical'
      'bg-danger'
    when 'major'
      'bg-warning'
    when 'minor'
      'bg-info'
    else
      'bg-secondary'
    end
  end

  def priority_badge_class
    case priority
    when 'critical'
      'bg-danger'
    when 'high'
      'bg-danger'
    when 'normal'
      'bg-info'
    when 'low'
      'bg-success'
    else
      'bg-secondary'
    end
  end

  def status_badge_class
    case status
    when 'pending'
      'bg-warning'
    when 'approved'
      'bg-success'
    when 'rejected'
      'bg-danger'
    when 'in_progress'
      'bg-primary'
    when 'completed'
      'bg-secondary'
    else
      'bg-secondary'
    end
  end

  def status_display
    case status
    when 'pending'
      'Pending Review'
    when 'approved'
      'Approved'
    when 'rejected'
      'Rejected'
    when 'in_progress'
      'In Progress'
    when 'completed'
      'Completed'
    else
      status.humanize
    end
  end

  private

  def notify_supervisor_if_blocking
    if blocking
      supervisors = User.where(role: 'workshop_supervisor')
      supervisors.each do |supervisor|
        Notification.create!(
          user: supervisor,
          title: "Blocking Issue Found",
          message: "#{finding_type.humanize} finding: #{description}",
          link: "/vmcott/inspections/#{inspection_id}",
          notification_type: 'warning',
          notifiable: self
        )
      end
    end
  end
end