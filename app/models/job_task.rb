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
  validates :estimated_cost, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :actual_cost, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  
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
  scope :skipped, -> { where(status: 'skipped') }
  scope :by_position, -> { order(position: :asc) }
  
  def can_transition_to?(new_status)
    STATUS_TRANSITIONS[status]&.include?(new_status) || false
  end
  
  def transition_to!(new_status, user = nil)
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
      when 'blocked'
        update!(blocked_at: Time.current)
      end
      
      # Create audit log
      AuditLog.create!(
        user: user,
        action: "job_task_status_change",
        auditable: self,
        details: { 
          from: old_status, 
          to: new_status,
          task_name: name,
          job_id: inspection_job_id
        }
      )
    end
  rescue => e
    Rails.logger.error("Failed to transition task #{id}: #{e.message}")
    raise
  end
  
  def start!(user = nil)
    transition_to!('in_progress', user)
  end
  
  def complete!(user = nil)
    transition_to!('completed', user)
  end
  
  def block!(reason, user = nil)
    transition_to!('blocked', user)
    update!(blocked_reason: reason)
  end
  
  def skip!(user = nil)
    transition_to!('skipped', user)
  end
  
  def dependencies_met?
    depends_on.where(status: 'completed').count == depends_on.count
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
    
    # Get mechanic rate or use default
    rate = if assigned_mechanic.present?
             MechanicRate.current_for(assigned_mechanic, inspection_job.job_type) || 85.00
           else
             85.00
           end
    
    self.actual_cost = actual_hours * rate
    save! if changed?
  end
  
  def estimated_total_cost
    estimated_cost || (estimated_hours.to_f * 85.00)
  end
  
  def actual_total_cost
    actual_cost || (actual_hours.to_f * 85.00)
  end
  
  def progress_percentage
    return 0 unless actual_hours.present? && estimated_hours.present? && estimated_hours > 0
    [(actual_hours / estimated_hours) * 100, 100].min
  end
  
  def time_variance
    return 0 unless actual_hours.present? && estimated_hours.present?
    actual_hours - estimated_hours
  end
  
  def cost_variance
    return 0 unless actual_cost.present? && estimated_cost.present?
    actual_cost - estimated_cost
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
end