# app/models/work_session.rb
class WorkSession < ApplicationRecord
  belongs_to :job_task
  belongs_to :mechanic, class_name: 'User'
  belongs_to :updated_by, class_name: 'User', optional: true
  
  validates :started_at, presence: true
  validates :session_type, presence: true, inclusion: { 
    in: ['work', 'break', 'waiting', 'blocked'],
    message: "must be work, break, waiting, or blocked"
  }
  validates :duration_hours, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  
  # Callbacks
  before_save :calculate_duration, if: :ended_at_changed?
  after_save :update_job_task_total_time, if: :saved_change_to_ended_at?
  
  # Scopes
  scope :active, -> { where(ended_at: nil) }
  scope :completed, -> { where.not(ended_at: nil) }
  scope :today, -> { where('started_at >= ?', Time.current.beginning_of_day) }
  scope :this_week, -> { where('started_at >= ?', Time.current.beginning_of_week) }
  scope :this_month, -> { where('started_at >= ?', Time.current.beginning_of_month) }
  scope :by_mechanic, ->(mechanic_id) { where(mechanic_id: mechanic_id) }
  scope :by_job_task, ->(job_task_id) { where(job_task_id: job_task_id) }
  scope :work_sessions, -> { where(session_type: 'work') }
  scope :break_sessions, -> { where(session_type: 'break') }
  scope :waiting_sessions, -> { where(session_type: 'waiting') }
  
  def active?
    ended_at.nil?
  end
  
  def end_session!(user = nil)
    update!(ended_at: Time.current, updated_by: user)
  end
  
  def pause!(user = nil, reason = nil)
    update!(
      ended_at: Time.current,
      session_type: 'break',
      updated_by: user,
      notes: reason
    )
  end
  
  def resume!(user = nil)
    # Create a new work session
    job_task.work_sessions.create!(
      mechanic: mechanic,
      started_at: Time.current,
      session_type: 'work',
      updated_by: user,
      system_generated: true
    )
  end
  
  def duration_minutes
    return 0 unless ended_at && started_at
    ((ended_at - started_at) / 60).round
  end
  
  def duration_seconds
    return 0 unless ended_at && started_at
    (ended_at - started_at).round
  end
  
  def formatted_duration
    return "In progress" unless ended_at
    
    hours = duration_hours.to_i
    minutes = ((duration_hours - hours) * 60).round
    
    if hours > 0
      "#{hours}h #{minutes}m"
    else
      "#{minutes}m"
    end
  end
  
  def formatted_time_range
    started = started_at.strftime("%H:%M")
    ended = ended_at ? ended_at.strftime("%H:%M") : "In progress"
    "#{started} - #{ended}"
  end
  
  def day
    started_at.to_date
  end
  
  def work_order
    job_task&.inspection_job&.work_order
  end
  
  private
  
  def calculate_duration
    return unless ended_at.present? && started_at.present?
    self.duration_hours = ((ended_at - started_at) / 3600).round(2)
  end
  
  def update_job_task_total_time
    job_task.update_total_time! if job_task.present?
  end
end