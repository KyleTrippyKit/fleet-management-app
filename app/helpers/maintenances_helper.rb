module MaintenancesHelper
  # Returns the urgency label for a maintenance
  def urgency_label(maintenance)
    if maintenance.next_due_date
      days_diff = (maintenance.next_due_date - Date.today).to_i
      if days_diff < 0
        "Overdue!"
      elsif days_diff <= 30
        "Soon"
      else
        "OK"
      end
    else
      case maintenance.urgency&.downcase
      when "emergency" then "Emergency"
      when "scheduled" then "Scheduled"
      when "routine" then "Routine"
      else "N/A"
      end
    end
  end

  # Returns the badge CSS class based on urgency
  def urgency_badge_class(maintenance)
    if maintenance.next_due_date
      days_diff = (maintenance.next_due_date - Date.today).to_i
      if days_diff < 0
        "badge bg-danger"
      elsif days_diff <= 30
        "badge bg-warning text-dark"
      else
        "badge bg-success"
      end
    else
      case maintenance.urgency&.downcase
      when "emergency" then "badge bg-danger"
      when "scheduled" then "badge bg-warning text-dark"
      when "routine" then "badge bg-primary text-white"
      else "badge bg-secondary"
      end
    end
  end

  # Full badge HTML for urgency
  def urgency_badge(maintenance)
    content_tag(:span, urgency_label(maintenance), class: urgency_badge_class(maintenance))
  end
end
