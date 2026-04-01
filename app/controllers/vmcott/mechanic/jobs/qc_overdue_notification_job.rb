# app/jobs/qc_overdue_notification_job.rb
class QcOverdueNotificationJob < ApplicationJob
  queue_as :default
  
  def perform
    # Find jobs that have been waiting for QC for more than 24 hours
    overdue_qc = MechanicAssignment
      .where(status: 'qc_requested')
      .where('qc_requested_at < ?', 24.hours.ago)
      .includes(inspection_job: { inspection: :vehicle })
    
    overdue_qc.each do |assignment|
      # Notify supervisor
      Notification.create!(
        user: User.where(role: 'workshop_supervisor'),
        title: "⚠️ QC Overdue",
        message: "Job ##{assignment.inspection_job.id} for vehicle #{assignment.inspection_job.inspection.vehicle.license_plate} has been waiting for QC for over 24 hours.",
        link: "/vmcott/workshop_supervisor/jobs/#{assignment.inspection_job.id}",
        notification_type: 'warning',
        notifiable: assignment
      )
      
      # Notify QC team
      Notification.create!(
        user: User.where(role: 'inspector'),
        title: "⚠️ QC Overdue",
        message: "Job ##{assignment.inspection_job.id} is waiting for your review.",
        link: "/vmcott/inspector/qc/#{assignment.inspection_job.inspection.id}",
        notification_type: 'warning',
        notifiable: assignment
      )
    end
  end
end