# app/helpers/workflow_helper.rb
module WorkflowHelper
  def workflow_status_badge(status)
    badges = {
      # Intake Phase
      'draft' => 'bg-secondary',
      'pending_inspection' => 'bg-secondary',
      
      # Inspection Phase
      'inspection_in_progress' => 'bg-info',
      'pending_mechanic_review' => 'bg-info',
      
      # Job Creation Phase
      'pending_supervisor_review' => 'bg-warning',
      
      # Quotation Phase
      'awaiting_approval' => 'bg-warning',
      'approved' => 'bg-primary',
      
      # Parts + Job Bundled Phase
      'ready_for_work' => 'bg-success',
      'in_progress' => 'bg-primary',
      
      # Quality Control Phase
      'ready_for_pickup' => 'bg-success',
      'completed' => 'bg-success',
      'on_hold' => 'bg-danger',
      'cancelled' => 'bg-secondary'
    }
    
    content_tag(:span, status.humanize, class: "badge #{badges[status] || 'bg-secondary'}")
  end
  
  def workflow_step_indicator(current_status, step_name, step_status)
    step_index = {
      'draft' => 1,
      'pending_inspection' => 2,
      'inspection_in_progress' => 3,
      'pending_mechanic_review' => 4,
      'pending_supervisor_review' => 5,
      'awaiting_approval' => 6,
      'approved' => 7,
      'ready_for_work' => 8,
      'in_progress' => 9,
      'ready_for_pickup' => 10,
      'completed' => 11,
      'on_hold' => 12,
      'cancelled' => 13
    }
    
    current_step = step_index[current_status] || 0
    step_number = step_index[step_status] || 0
    
    if step_number < current_step
      'completed'
    elsif step_number == current_step
      'current'
    else
      'pending'
    end
  end
  
  def workflow_progress_percentage(status)
    percentages = {
      'draft' => 0,
      'pending_inspection' => 5,
      'inspection_in_progress' => 10,
      'pending_mechanic_review' => 20,
      'pending_supervisor_review' => 30,
      'awaiting_approval' => 40,
      'approved' => 50,
      'ready_for_work' => 60,
      'in_progress' => 70,
      'ready_for_pickup' => 90,
      'completed' => 100,
      'on_hold' => 50,
      'cancelled' => 0
    }
    percentages[status] || 0
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
      'pending' => 'bg-secondary',
      'pending_approval' => 'bg-warning',
      'approved' => 'bg-primary',
      'assigned' => 'bg-info',
      'in_progress' => 'bg-primary',
      'blocked' => 'bg-danger',
      'rework_needed' => 'bg-danger',
      'qc_pending' => 'bg-info',
      'approved_qc' => 'bg-success',
      'completed' => 'bg-success'
    }
    
    content_tag(:span, status.humanize, class: "badge #{badges[status] || 'bg-secondary'}")
  end
  
  def parts_request_status_badge(status)
    badges = {
      'pending_approval' => 'bg-warning',
      'approved' => 'bg-success',
      'rejected' => 'bg-danger',
      'issued' => 'bg-info',
      'parts_received' => 'bg-success',
      'needs_order' => 'bg-danger',
      'ordered' => 'bg-primary'
    }
    
    content_tag(:span, status.humanize, class: "badge #{badges[status] || 'bg-secondary'}")
  end
  
  def can_start_job?(job)
    job.status == 'approved' && job.inspection.ready_for_execution?
  end
  
  def can_pause_job?(job)
    job.status == 'in_progress'
  end
  
  def can_complete_job?(job)
    job.status == 'in_progress' && job.work_completed?
  end
  
  def show_approval_checkboxes?(inspection)
    inspection.status == 'awaiting_approval'
  end
  
  def progress_percentage(inspection)
    workflow_progress_percentage(inspection.status)
  end
  
  def timeline_events(inspection)
    events = []
    
    events << {
      date: inspection.created_at,
      title: "Inspection Created",
      description: "Inspection record created",
      icon: "bi-file-earmark-plus",
      status: inspection.status != 'draft' ? "completed" : "current"
    }
    
    if inspection.status != 'draft'
      events << {
        date: inspection.updated_at,
        title: "Pending Inspection",
        description: "Ready for inspection",
        icon: "bi-clock",
        status: inspection.status != 'pending_inspection' ? "completed" : "current"
      }
    end
    
    if inspection.status != 'pending_inspection'
      events << {
        date: inspection.started_at || inspection.updated_at,
        title: "Inspection Started",
        description: "Technical inspection in progress",
        icon: "bi-search",
        status: inspection.status != 'inspection_in_progress' ? "completed" : "current"
      }
    end
    
    if inspection.status != 'inspection_in_progress' && inspection.status != 'pending_mechanic_review'
      events << {
        date: inspection.updated_at,
        title: "Mechanic Review",
        description: "Mechanic reviewing findings",
        icon: "bi-wrench",
        status: inspection.status != 'pending_mechanic_review' ? "completed" : "current"
      }
    end
    
    if inspection.status != 'pending_mechanic_review' && inspection.status != 'pending_supervisor_review'
      events << {
        date: inspection.updated_at,
        title: "Supervisor Review",
        description: "Supervisor reviewing jobs",
        icon: "bi-clipboard-check",
        status: inspection.status != 'pending_supervisor_review' ? "completed" : "current"
      }
    end
    
    if inspection.status != 'pending_supervisor_review' && inspection.status != 'awaiting_approval'
      events << {
        date: inspection.updated_at,
        title: "Jobs Created",
        description: "Jobs created for repair work",
        icon: "bi-list-check",
        status: inspection.status != 'awaiting_approval' ? "completed" : "current"
      }
    end
    
    if inspection.status != 'awaiting_approval' && inspection.status != 'approved'
      events << {
        date: inspection.updated_at,
        title: "Customer Approval",
        description: "Customer approved the work",
        icon: "bi-check-circle",
        status: inspection.status != 'approved' ? "completed" : "current"
      }
    end
    
    if inspection.inspection_jobs.any? && inspection.status != 'approved'
      completed_jobs = inspection.inspection_jobs.where(status: 'completed').count
      total_jobs = inspection.inspection_jobs.count
      
      events << {
        date: inspection.inspection_jobs.where.not(completed_at: nil).first&.completed_at || Time.current,
        title: "Repair Work",
        description: "#{completed_jobs} of #{total_jobs} repair jobs completed",
        icon: "bi-tools",
        status: completed_jobs == total_jobs ? "completed" : "current"
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
        status: inspection.status == 'completed' ? "completed" : "current"
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
  
  def rework_badge(inspection)
    return unless inspection.rework_required
    
    content_tag(:span, "⚠️ Rework Required: #{inspection.rework_reason}", 
                class: "badge bg-danger")
  end
  
  def qc_status_badge(inspection)
    if inspection.qc_passed_at.present?
      content_tag(:span, "✅ QC Passed: #{inspection.qc_passed_at.strftime('%Y-%m-%d')}", 
                  class: "badge bg-success")
    elsif inspection.qc_failed_at.present?
      content_tag(:span, "❌ QC Failed: #{inspection.qc_failure_reason}", 
                  class: "badge bg-danger")
    else
      content_tag(:span, "⏳ QC Pending", class: "badge bg-warning")
    end
  end
end