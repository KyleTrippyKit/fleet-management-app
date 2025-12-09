module MaintenancesHelper
  def urgency_label(maintenance)
    return "Completed" if maintenance.status == "Completed"
    return "Soon" if maintenance.date.present? && maintenance.date <= Date.today + 7.days

    "Pending"
  end

  def urgency_badge_class(maintenance)
    case urgency_label(maintenance)
    when "Completed" then "bg-success"
    when "Soon"      then "bg-warning text-dark"
    else "bg-primary"
    end
  end
end
