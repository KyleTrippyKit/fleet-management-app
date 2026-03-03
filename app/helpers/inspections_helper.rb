module InspectionsHelper
  def inspection_status_color(status)
    case status
    when 'pending_inspection' then 'secondary'
    when 'inspection_completed' then 'primary'
    when 'pending_mechanic_review' then 'warning'
    when 'parts_coordinator_review' then 'info'
    when 'billing_review' then 'warning'
    when 'awaiting_customer_approval' then 'warning'
    when 'approved_for_repair' then 'success'
    when 'in_progress' then 'primary'
    when 'ready_for_qc' then 'info'
    when 'qc_completed' then 'success'
    when 'ready_for_pickup' then 'success'
    when 'completed' then 'success'
    else 'secondary'
    end
  end

  def inspection_status_icon(status)
    case status
    when 'pending_inspection' then 'bi-hourglass'
    when 'inspection_completed' then 'bi-check-circle'
    when 'pending_mechanic_review' then 'bi-clock-history'
    when 'parts_coordinator_review' then 'bi-box-seam'
    when 'billing_review' then 'bi-cash'
    when 'awaiting_customer_approval' then 'bi-clock'
    when 'approved_for_repair' then 'bi-check-circle-fill'
    when 'in_progress' then 'bi-wrench'
    when 'ready_for_qc' then 'bi-clipboard-check'
    when 'qc_completed' then 'bi-check-circle-fill'
    when 'ready_for_pickup' then 'bi-truck'
    when 'completed' then 'bi-check-circle-fill'
    else 'bi-question-circle'
    end
  end

  def parts_request_status_badge(status)
    badge_class = case status
    when 'pending' then 'bg-secondary'
    when 'parts_coordinator_notified' then 'bg-info'
    when 'billing_notified' then 'bg-warning'
    when 'rfq_sent' then 'bg-primary'
    when 'quotations_received' then 'bg-success'
    when 'finance_review' then 'bg-dark'
    when 'purchase_order_created' then 'bg-success'
    when 'parts_ordered' then 'bg-info'
    when 'parts_received' then 'bg-success'
    when 'approved' then 'bg-success'
    when 'rejected' then 'bg-danger'
    else 'bg-secondary'
    end
    
    content_tag :span, status.titleize, class: "badge #{badge_class}"
  end

  # NEW: Human-readable inspection status
  def inspection_status_display(status)
    case status
    when 'pending_inspection'
      "⏳ Waiting for Inspection"
    when 'inspection_completed'
      "✅ Inspection Completed"
    when 'pending_mechanic_review'
      "👨‍🔧 Pending Mechanic Review"
    when 'parts_coordinator_review'
      "📦 Parts Coordinator Review"
    when 'billing_review'
      "💰 Billing Review"
    when 'awaiting_customer_approval'
      "⏳ Awaiting Customer Approval"
    when 'approved_for_repair'
      "✅ Approved for Repair"
    when 'in_progress'
      "🔧 Repair in Progress"
    when 'ready_for_qc'
      "🔍 Ready for QC"
    when 'qc_completed'
      "✅ QC Completed"
    when 'ready_for_pickup'
      "🚗 Ready for Pickup"
    when 'completed'
      "✅ Completed"
    else
      status.titleize
    end
  end

  # NEW: Badge with icon for inspection status
  def inspection_status_badge(status)
    content_tag :span, class: "badge bg-#{inspection_status_color(status)} px-3 py-2" do
      concat content_tag(:i, '', class: "#{inspection_status_icon(status)} me-1")
      concat " "
      concat inspection_status_display(status)
    end
  end

  # NEW: Progress percentage for workflow
  def inspection_workflow_progress(inspection)
    case inspection.status
    when 'pending_inspection'
      10
    when 'inspection_completed'
      20
    when 'pending_mechanic_review'
      30
    when 'parts_coordinator_review'
      40
    when 'billing_review'
      50
    when 'awaiting_customer_approval'
      60
    when 'approved_for_repair'
      70
    when 'in_progress'
      80
    when 'ready_for_qc'
      85
    when 'qc_completed'
      90
    when 'ready_for_pickup'
      95
    when 'completed'
      100
    else
      0
    end
  end

  # NEW: Next step in workflow
  def inspection_next_step(inspection)
    case inspection.status
    when 'pending_inspection'
      "Complete inspection"
    when 'inspection_completed'
      "Send for mechanic review"
    when 'pending_mechanic_review'
      "Mechanic to review and verify"
    when 'parts_coordinator_review'
      "Process parts requests"
    when 'billing_review'
      "Review and approve"
    when 'awaiting_customer_approval'
      "Wait for customer approval"
    when 'approved_for_repair'
      "Mechanic to start work"
    when 'in_progress'
      "Complete repairs"
    when 'ready_for_qc'
      "Perform quality check"
    when 'qc_completed'
      "Prepare for pickup"
    when 'ready_for_pickup'
      "Agency to pick up"
    when 'completed'
      "All done"
    else
      "Next step"
    end
  end
end