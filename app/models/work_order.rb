# app/models/work_order.rb
class WorkOrder < ApplicationRecord
  belongs_to :vehicle
  belongs_to :customer, polymorphic: true, optional: true
  belongs_to :created_by, class_name: 'User', optional: true
  belongs_to :updated_by, class_name: 'User', optional: true
  
  has_many :inspections, dependent: :destroy
  has_many :inspection_jobs, through: :inspections
  has_many :job_tasks, through: :inspection_jobs
  has_many :work_sessions, through: :job_tasks
  has_many :quotations, dependent: :destroy
  has_many :payments, dependent: :destroy
  has_many :invoices, dependent: :destroy
  has_many :findings, dependent: :destroy
  has_many :audit_logs, as: :auditable, dependent: :nullify
  
  validates :work_order_number, presence: true, uniqueness: true
  validates :status, presence: true, inclusion: {
    in: ['received', 'inspected', 'awaiting_approval', 'approved', 
         'in_progress', 'on_hold', 'ready_for_pickup', 'completed', 'cancelled']
  }
  validates :payment_status, inclusion: { in: ['pending', 'partial', 'paid', 'on_account'] }, allow_nil: true
  
  # Callbacks
  before_validation :generate_work_order_number, on: :create
  before_save :calculate_totals, if: :will_save_change_to_total_amount?
  
  # State transitions
  STATUS_TRANSITIONS = {
    'received' => ['inspected'],
    'inspected' => ['awaiting_approval'],
    'awaiting_approval' => ['approved', 'on_hold'],
    'approved' => ['in_progress'],
    'in_progress' => ['completed', 'on_hold'],
    'on_hold' => ['in_progress', 'cancelled'],
    'ready_for_pickup' => ['completed'],
    'completed' => [],
    'cancelled' => []
  }
  
  # Scopes
  scope :received, -> { where(status: 'received') }
  scope :inspected, -> { where(status: 'inspected') }
  scope :awaiting_approval, -> { where(status: 'awaiting_approval') }
  scope :approved, -> { where(status: 'approved') }
  scope :in_progress, -> { where(status: 'in_progress') }
  scope :on_hold, -> { where(status: 'on_hold') }
  scope :ready_for_pickup, -> { where(status: 'ready_for_pickup') }
  scope :completed, -> { where(status: 'completed') }
  scope :cancelled, -> { where(status: 'cancelled') }
  scope :by_date_range, ->(start_date, end_date) { where(created_at: start_date..end_date) }
  
  def can_transition_to?(new_status)
    STATUS_TRANSITIONS[status]&.include?(new_status) || false
  end
  
  def transition_to!(new_status, user = nil)
    raise "Invalid transition from #{status} to #{new_status}" unless can_transition_to?(new_status)
    
    transaction do
      old_status = status
      update!(status: new_status)
      
      # Handle side effects
      case new_status
      when 'inspected'
        update!(inspected_at: Time.current)
      when 'approved'
        update!(approved_at: Time.current)
      when 'in_progress'
        update!(started_at: Time.current)
      when 'completed'
        update!(completed_at: Time.current)
        generate_pickup_code if ready_for_pickup?
      when 'cancelled'
        release_all_part_reservations
      end
      
      # Create audit log with correct column names
      if defined?(AuditLog) && AuditLog.table_exists?
        AuditLog.create!(
          user_id: user&.id,
          record_type: 'WorkOrder',
          record_id: id,
          action: 'work_order_status_change',
          audit_changes: { from: old_status, to: new_status },
          ip_address: request&.remote_ip,
          note: "Work order status changed from #{old_status} to #{new_status}"
        )
      end
    end
  end
  
  def customer_name
    if customer.is_a?(User)
      customer.name
    elsif customer.is_a?(Agency)
      customer.name
    else
      "Walk-in Customer"
    end
  end
  
  def amount_paid
    payments.sum(:amount)
  end
  
  def balance_due
    total_amount - amount_paid
  end
  
  def paid?
    balance_due <= 0
  end
  
  def partially_paid?
    amount_paid > 0 && balance_due > 0
  end
  
  def total_labor_cost
    inspection_jobs.sum(:actual_labor_cost)
  end
  
  def total_parts_cost
    inspection_jobs.sum(:actual_parts_cost)
  end
  
  def has_blocking_finding?
    findings.where(blocking: true, status: 'pending').exists?
  end
  
  def all_jobs_completed?
    inspection_jobs.where.not(status: 'completed').empty?
  end
  
  def all_tasks_completed?
    job_tasks.where.not(status: 'completed').empty?
  end
  
  def generate_pickup_code
    self.pickup_code = SecureRandom.hex(4).upcase
    save!
  end
  
  def timeline_events
    events = []
    
    events << { event: "Work Order Created", date: created_at, description: "Work order ##{work_order_number} created" }
    events << { event: "Vehicle Received", date: received_at, description: "Vehicle received at facility" } if received_at
    events << { event: "Inspection Completed", date: inspected_at, description: "Inspection completed" } if inspected_at
    events << { event: "Awaiting Approval", date: updated_at, description: "Waiting for customer approval" } if status == 'awaiting_approval'
    events << { event: "Approved", date: approved_at, description: "Work approved by customer" } if approved_at
    events << { event: "Work Started", date: started_at, description: "Work began" } if started_at
    events << { event: "Ready for Pickup", date: ready_for_pickup_at, description: "Vehicle ready for pickup" } if ready_for_pickup_at
    events << { event: "Completed", date: completed_at, description: "Work order completed" } if completed_at
    
    events.sort_by { |e| e[:date] || Time.at(0) }
  end
  
  private
  
  def generate_work_order_number
    return if work_order_number.present?
    loop do
      self.work_order_number = "WO-#{Date.current.strftime('%Y%m%d')}-#{SecureRandom.hex(4).upcase}"
      break unless self.class.exists?(work_order_number: work_order_number)
    end
  end
  
  def calculate_totals
    self.total_amount = total_labor_cost + total_parts_cost
  end
  
  def release_all_part_reservations
    job_tasks.each do |task|
      task.work_sessions.each do |session|
        session.update!(ended_at: Time.current) if session.active?
      end
    end
  end
end