module InspectionsHelper
  def inspection_status_color(status)
    case status
    when 'pending_inspection' then 'secondary'
    when 'inspection_completed' then 'primary'
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
end