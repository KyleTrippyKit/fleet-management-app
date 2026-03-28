# app/models/finding.rb
class Finding < ApplicationRecord
  belongs_to :inspection
  belongs_to :inspection_job, optional: true
  belongs_to :created_by, class_name: 'User', optional: true
  belongs_to :job, class_name: 'InspectionJob', optional: true
  belongs_to :work_order, optional: true

  validates :finding_type, presence: true
  validates :description, presence: true
  validates :severity, inclusion: { in: ['critical', 'major', 'minor'] }
  
  # Add priority validation
  validates :priority, inclusion: { in: ['low', 'normal', 'high', 'critical'] }, allow_nil: true

  attribute :job_created, :boolean, default: false
  attribute :priority, :string, default: 'normal'

  enum :finding_type, {
    initial: 'initial',
    mechanic: 'mechanic',
    final: 'final'
  }

  scope :blocking, -> { where(blocking: true) }
  scope :unapproved, -> { where(client_approved: false) }
  scope :pending_job_creation, -> { where(job_created: false) }

  after_create :notify_supervisor_if_blocking

  private

  def notify_supervisor_if_blocking
    if blocking
      supervisor = User.where(role: 'workshop_supervisor').first
      return unless supervisor
      
      Notification.create!(
        title: "Blocking Issue Found",
        message: "#{finding_type.humanize} finding: #{description}",
        link: "/vmcott/inspections/#{inspection_id}",
        user_id: supervisor.id
      )
    end
  end
end