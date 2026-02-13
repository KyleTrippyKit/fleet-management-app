module PtscDashboardHelper
  def alert_badge_class(alert)
    level = (alert.level || "info").to_s

    case level
    when "critical", "high" then "bg-danger"
    when "warning", "medium" then "bg-warning text-dark"
    when "success" then "bg-success"
    else "bg-info text-dark"
    end
  end
end
