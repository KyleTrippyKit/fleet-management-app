module RfqsHelper
  def urgency_badge_color(urgency)
    case urgency&.downcase
    when 'urgent', 'high'
      'danger'
    when 'medium'
      'warning'
    when 'low'
      'info'
    else
      'secondary'
    end
  end
end