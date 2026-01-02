# app/helpers/analytics_helper.rb
module AnalyticsHelper
  # Owner badge class for analytics page
  def owner_badge_class_analytics(owner)
    "owner-#{owner.parameterize(separator: '_')}"
  end
  
  # Utilization progress bar for analytics cards
  def utilization_progress_bar(utilization)
    color_class = case utilization.to_f
                  when 0..30 then 'bg-danger'
                  when 31..70 then 'bg-warning'
                  else 'bg-success'
                  end
    
    content_tag(:div, class: "progress", style: "height: 6px;") do
      content_tag(:div, "", 
        class: "progress-bar #{color_class}",
        style: "width: #{utilization}%;",
        role: "progressbar",
        "aria-valuenow": utilization,
        "aria-valuemin": "0",
        "aria-valuemax": "100")
    end
  end
  
  # Analytics card color based on utilization
  def analytics_card_color(utilization)
    case utilization.to_f
    when 0..30 then '#FF6B6B'  # Red for low
    when 31..70 then '#FFA726' # Orange for medium
    else '#4CAF50'             # Green for high
    end
  end
end