# app/models/job_task.rb
class JobTask < ApplicationRecord
  belongs_to :inspection_job
  belongs_to :assigned_mechanic, class_name: 'User', optional: true
  belongs_to :finding, optional: true
  
  has_many :work_sessions, dependent: :destroy
  has_many :dependencies, class_name: 'JobTaskDependency', foreign_key: :job_task_id
  has_many :depends_on, through: :dependencies, source: :depends_on_task
  
  # Validations
  validates :name, presence: true
  validates :status, presence: true, inclusion: {
    in: ['pending', 'approved', 'in_progress', 'blocked', 'completed', 'skipped']
  }
  validates :estimated_hours, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :actual_hours, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  
  # Callbacks
  after_save :update_job_total_time, if: :saved_change_to_actual_hours?
  
  # State transitions
  STATUS_TRANSITIONS = {
    'pending' => ['approved', 'skipped'],
    'approved' => ['in_progress'],
    'in_progress' => ['blocked', 'completed'],
    'blocked' => ['in_progress'],
    'completed' => [],
    'skipped' => []
  }
  
  # Scopes
  scope :pending, -> { where(status: 'pending') }
  scope :approved, -> { where(status: 'approved') }
  scope :in_progress, -> { where(status: 'in_progress') }
  scope :blocked, -> { where(status: 'blocked') }
  scope :completed, -> { where(status: 'completed') }
  
  def can_transition_to?(new_status)
    STATUS_TRANSITIONS[status]&.include?(new_status) || false
  end
  
  # =====================================================
  # CRITICAL: ENFORCED START METHOD
  # =====================================================
  
  def start!(user = nil, ip_address = nil)
    # 🔥 ENFORCEMENT: Check if job is ready for execution
    unless inspection_job&.inspection&.ready_for_execution?
      raise "Cannot start work: job not approved, payment not received, or parts not ready"
    end
    
    # Check if dependencies are satisfied
    unless dependencies_met?
      raise "Cannot start: missing dependencies"
    end
    
    # Check if job is not blocked
    if inspection_job.blocked?
      raise "Cannot start: job is blocked"
    end
    
    transition_to!('in_progress', user, ip_address)
    update(started_at: Time.current)
    
    # 🔥 UPDATE MECHANIC ASSIGNMENT
    assignment = MechanicAssignment.find_by(inspection_job: inspection_job, mechanic: assigned_mechanic)
    if assignment
      assignment.update!(
        status: 'in_progress',
        started_at: Time.current
      )
    end
    
    true
  end
  
  def can_start?
    return false unless status == 'approved'
    return false unless inspection_job&.inspection&.ready_for_execution?
    return false if inspection_job.blocked?
    dependencies_met?
  end
  
  def dependencies_met?
    depends_on.where(status: 'completed').count == depends_on.count
  end
  
  def transition_to!(new_status, user = nil, ip_address = nil)
    raise "Invalid transition from #{status} to #{new_status}" unless can_transition_to?(new_status)
    
    transaction do
      old_status = status
      update!(status: new_status)
      
      case new_status
      when 'in_progress'
        update!(started_at: Time.current)
      when 'completed'
        update!(completed_at: Time.current)
        calculate_actual_cost!
        check_job_completion
        
        # Update mechanic assignment to completed
        assignment = MechanicAssignment.find_by(inspection_job: inspection_job, mechanic: assigned_mechanic)
        if assignment
          assignment.update!(
            status: 'completed',
            completed_at: Time.current,
            mechanic_notes: "#{assignment.mechanic_notes}\nTask #{name} completed"
          )
        end
      when 'blocked'
        update!(blocked_at: Time.current)
      end
      
      # Create audit log
      create_audit_log(old_status, new_status, user, ip_address)
    end
  end
  
  def complete!(user = nil, ip_address = nil)
    transition_to!('completed', user, ip_address)
  end
  
  def block!(reason, user = nil, ip_address = nil)
    transition_to!('blocked', user, ip_address)
    update!(blocked_reason: reason)
  end
  
  def skip!(user = nil, ip_address = nil)
    transition_to!('skipped', user, ip_address)
  end
  
  def missing_dependencies
    depends_on.where.not(status: 'completed')
  end
  
  def active_work_session
    work_sessions.where(ended_at: nil).first
  end
  
  def total_work_time
    work_sessions.sum(:duration_hours)
  end
  
  def update_total_time!
    total = work_sessions.sum(:duration_hours)
    update!(actual_hours: total)
    calculate_actual_cost!
  end
  
  def calculate_actual_cost!
    return unless actual_hours.present?
    
    rate = if assigned_mechanic.present?
             MechanicRate.current_for(assigned_mechanic, inspection_job.job_type) || 85.00
           else
             85.00
           end
    
    self.actual_cost = actual_hours * rate
    save! if changed?
  end
  
  def progress_percentage
    return 0 unless actual_hours.present? && estimated_hours.present? && estimated_hours > 0
    [(actual_hours / estimated_hours) * 100, 100].min
  end
  
  private
  
  def check_job_completion
    if inspection_job.job_tasks.where.not(status: 'completed').empty?
      inspection_job.complete!
    end
  end
  
  def update_job_total_time
    inspection_job.update_total_time! if inspection_job.present?
  end
  
  def create_audit_log(old_status, new_status, user, ip_address)
    return unless defined?(AuditLog) && AuditLog.table_exists?
    
    audit_log_data = { 
      from: old_status, 
      to: new_status,
      task_name: name,
      job_id: inspection_job_id
    }
    
    AuditLog.create!(
      user_id: user&.id,
      record_type: 'JobTask',
      record_id: id,
      action: 'job_task_status_change',
      audit_changes: audit_log_data.to_json,
      ip_address: ip_address,
      note: "Task status changed from #{old_status} to #{new_status}"
    )
  rescue => e
    Rails.logger.warn("Could not create audit log: #{e.message}")
  end
end