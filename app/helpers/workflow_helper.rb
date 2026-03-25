# app/helpers/workflow_helper.rb
module WorkflowHelper
  def workflow_status_badge(status)
    badges = {
      'pending_inspection' => 'bg-secondary',
      'pending_mechanic_review' => 'bg-info',
      'pending_parts_coordinator' => 'bg-primary',
      'pending_supervisor_review' => 'bg-warning',
      'pending_procurement_quotation' => 'bg-info',
      'awaiting_client_approval' => 'bg-warning',
      'approved_for_repair' => 'bg-success',
      'in_progress' => 'bg-primary',
      'paused' => 'bg-warning',
      'blocked' => 'bg-danger',
      'rework_needed' => 'bg-danger',
      'ready_for_qc' => 'bg-info',
      'ready_for_pickup' => 'bg-success',
      'completed' => 'bg-success',
      'closed' => 'bg-secondary',
      'on_hold' => 'bg-dark'
    }
    
    content_tag(:span, status.humanize, class: "badge #{badges[status]}")
  end
  
  def workflow_type_label(type)
    labels = {
      'payment_before_work' => '💰 Payment Required Before Work',
      'work_before_payment' => '🔧 Work Before Payment'
    }
    labels[type] || type.humanize
  end
  
  def client_approval_status_badge(status)
    case status
    when 'full_approved'
      content_tag(:span, '✓ Fully Approved', class: 'badge bg-success')
    when 'partial_approved'
      content_tag(:span, '⚠️ Partially Approved', class: 'badge bg-warning')
    when 'pending'
      content_tag(:span, '⏳ Awaiting Approval', class: 'badge bg-secondary')
    when 'rejected'
      content_tag(:span, '✗ Rejected', class: 'badge bg-danger')
    end
  end
  
  def job_status_badge(status)
    badges = {
      'pending_mechanic_review' => 'bg-secondary',
      'pending_parts_review' => 'bg-info',
      'pending_mechanic_work' => 'bg-info',
      'in_progress' => 'bg-primary',
      'paused' => 'bg-warning',
      'blocked' => 'bg-danger',
      'rework_needed' => 'bg-danger',
      'completed' => 'bg-success'
    }
    
    content_tag(:span, status.humanize, class: "badge #{badges[status]}")
  end
  
  def can_start_job?(job)
    job.can_start? && job.inspection.client_can_start_work?
  end
  
  def can_pause_job?(job)
    job.can_pause?
  end
  
  def can_complete_job?(job)
    job.can_complete? && job.inspection.job_approved?(job.id)
  end
  
  def show_approval_checkboxes?(inspection)
    inspection.awaiting_client_approval? || inspection.awaiting_client_approval_original? || inspection.awaiting_client_approval_additional?
  end
  
  def progress_percentage(inspection)
    total_jobs = inspection.inspection_jobs.count
    return 0 if total_jobs == 0
    
    completed_jobs = inspection.inspection_jobs.where(status: 'completed').count
    ((completed_jobs.to_f / total_jobs) * 100).round
  end
  
  def timeline_events(inspection)
    events = []
    
    events << {
      date: inspection.received_at,
      title: "Vehicle Received",
      description: "Vehicle received at VMCOTT",
      icon: "bi-box-arrow-in-right",
      status: "completed"
    }
    
    if inspection.no_work_needed?
      events << {
        date: inspection.completed_at,
        title: "Inspection Complete",
        description: "No work required",
        icon: "bi-check-circle",
        status: "completed"
      }
      return events
    end
    
    if inspection.created_at.present?
      events << {
        date: inspection.created_at,
        title: "Inspection Started",
        description: "Technical inspection in progress",
        icon: "bi-search",
        status: inspection.status != 'pending_inspection' ? "completed" : "in_progress"
      }
    end
    
    if inspection.inspection_jobs.any?
      completed_jobs = inspection.inspection_jobs.where.not(completed_at: nil).count
      total_jobs = inspection.inspection_jobs.count
      
      events << {
        date: inspection.inspection_jobs.where.not(completed_at: nil).first&.completed_at || Time.current,
        title: "Repair Work",
        description: "#{completed_jobs} of #{total_jobs} repair jobs completed",
        icon: "bi-tools",
        status: completed_jobs == total_jobs ? "completed" : "in_progress"
      }
    end
    
    if inspection.status == 'ready_for_pickup' || inspection.status == 'completed'
      events << {
        date: inspection.ready_for_pickup_at || inspection.updated_at,
        title: "Quality Control Passed",
        description: "Vehicle passed quality control inspection",
        icon: "bi-check-circle",
        status: "completed"
      }
    end
    
    if inspection.ready_for_pickup_at.present?
      events << {
        date: inspection.ready_for_pickup_at,
        title: "Ready for Pickup",
        description: "Your vehicle is ready for pickup",
        icon: "bi-truck",
        status: inspection.status == 'completed' ? "completed" : "in_progress"
      }
    end
    
    if inspection.completed?
      events << {
        date: inspection.actual_pickup_date || inspection.updated_at,
        title: "Vehicle Picked Up",
        description: "Vehicle released to customer",
        icon: "bi-check-circle-fill",
        status: "completed"
      }
    end
    
    events.sort_by { |t| t[:date] || Time.current }
  end
end