class MechanicAssignment < ApplicationRecord
  belongs_to :inspection_job
  belongs_to :mechanic, class_name: 'User'
  
  validates :status, presence: true
  
  # Rails 7+ enum syntax
  enum :status, {
    assigned: 'assigned',
    in_progress: 'in_progress',
    waiting_parts: 'waiting_parts',
    completed: 'completed',
    qc_requested: 'qc_requested',
    qc_passed: 'qc_passed',
    qc_failed: 'qc_failed'
  }

  # Scopes
  scope :active, -> { where(status: [:assigned, :in_progress, :waiting_parts]) }
  scope :needing_qc, -> { where(status: :qc_requested) }

  # Instance methods
  def start!
    update(status: :in_progress, started_at: Time.current)
  end

  def complete!(notes = nil)
    update(
      status: :completed,
      completed_at: Time.current,
      mechanic_notes: notes
    )
    inspection_job.inspection.check_jobs_completion!
  end

  def request_qc!
    update(status: :qc_requested, qc_requested_at: Time.current)
    QcNotificationJob.perform_later(id) if defined?(QcNotificationJob)
  end

  def pass_qc!(notes = nil)
    update(
      status: :qc_passed,
      qc_completed_at: Time.current,
      qc_notes: notes
    )
    inspection_job.update(completed_at: Time.current)
    inspection_job.inspection.check_jobs_completion!
  end

  def fail_qc!(notes)
    update(
      status: :qc_failed,
      qc_completed_at: Time.current,
      qc_notes: notes
    )
  end
end