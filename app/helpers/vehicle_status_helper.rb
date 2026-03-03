module VehicleStatusHelper
  def status_badge(status)
    return content_tag(:span, "Unknown", class: "badge bg-secondary") if status.blank?
    
    css_class = case status.to_s
    when 'at_vmcott'
      'bg-primary'
    when 'pending_inspection'
      'bg-info'
    when 'approved_for_repair'
      'bg-success'
    when 'in_progress'
      'bg-warning text-dark'
    when 'ready_for_qc'
      'bg-secondary'
    when 'ready_for_pickup'
      'bg-success'
    else
      'bg-secondary'
    end
    
    content_tag(:span, status.to_s.titleize, class: "badge #{css_class}")
  end
  
  def vehicle_status_badge(vehicle)
    return content_tag(:span, "No Status", class: "badge bg-secondary") unless vehicle
    
    status = vehicle.current_status || vehicle.status
    status_badge(status)
  end
end