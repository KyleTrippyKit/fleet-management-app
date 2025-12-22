module MaintenancesHelper
  # Returns the urgency label for a maintenance
  def urgency_label(maintenance)
    return "N/A" if maintenance.nil?
    
    if maintenance.overdue?
      "Overdue!"
    elsif maintenance.active?
      "Active"
    elsif maintenance.upcoming?
      "Upcoming"
    else
      case maintenance.urgency&.downcase
      when "emergency" then "Emergency"
      when "scheduled" then "Scheduled"
      when "routine" then "Routine"
      else "Not Specified"
      end
    end
  end

  # Returns the badge CSS class for a maintenance's urgency (for use in form previews)
  def maintenance_urgency_badge_class(maintenance)
    return "bg-secondary" if maintenance.nil? || maintenance.urgency.blank?
    
    case maintenance.urgency.downcase
    when "emergency"
      "bg-danger"
    when "scheduled"
      "bg-warning text-dark"
    when "routine"
      "bg-primary"
    else
      "bg-secondary"
    end
  end

  # Returns the badge CSS class based on status and urgency (for general use)
  def urgency_badge_class(maintenance)
    return "badge bg-secondary" if maintenance.nil?
    
    if maintenance.overdue?
      "badge bg-danger"
    elsif maintenance.active?
      "badge bg-info"
    elsif maintenance.upcoming?
      "badge bg-warning text-dark"
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

  # Status badge
  def status_badge(maintenance)
    return content_tag(:span, "N/A", class: "badge bg-secondary") if maintenance.nil?
    
    classes = "badge #{maintenance.status_badge_class}"
    content_tag(:span, maintenance.status, class: classes)
  end

  # Progress bar for maintenance
  def progress_bar(maintenance, options = {})
    return content_tag(:span, "N/A", class: "text-muted") if maintenance.nil?
    
    width = options[:width] || "80px"
    height = options[:height] || "6px"
    show_label = options[:show_label] || false
    
    content = content_tag(:div, class: "progress", style: "height: #{height}; width: #{width};") do
      content_tag(:div, "", 
        class: "progress-bar #{maintenance.status_badge_class.gsub('bg-', 'bg-')}",
        style: "width: #{maintenance.progress_percentage}%",
        role: "progressbar",
        "aria-valuenow": maintenance.progress_percentage,
        "aria-valuemin": "0",
        "aria-valuemax": "100"
      )
    end
    
    if show_label
      content_tag(:div, class: "d-flex align-items-center") do
        content + content_tag(:span, "#{maintenance.progress_percentage}%", class: "small ms-2")
      end
    else
      content
    end
  end

  # Format duration display
  def format_duration(start_date, end_date)
    return "N/A" unless start_date && end_date
    days = (end_date - start_date).to_i + 1
    "#{days} #{'day'.pluralize(days)}"
  end

  # Owner badge color (returns CSS class without "bg-" prefix)
  def owner_color(owner)
    return "secondary" if owner.blank?
    
    colors = {
      'Fleet Management' => 'primary',
      'Operations' => 'success',
      'Maintenance' => 'warning',
      'Administration' => 'info',
      'Other' => 'secondary'
    }
    colors[owner] || 'dark'
  end

  # Owner badge class (returns full CSS class with "bg-" prefix)
  def owner_badge_class(owner)
    return "bg-secondary" if owner.blank?
    
    colors = {
      'Fleet Management' => 'bg-primary',
      'Operations' => 'bg-success',
      'Maintenance' => 'bg-warning',
      'Administration' => 'bg-info',
      'Other' => 'bg-secondary'
    }
    colors[owner] || 'bg-dark'
  end

  # Format cost display
  def format_cost(cost)
    return "N/A" unless cost
    number_to_currency(cost, unit: "R")
  end

  # Timeline color based on urgency
  def timeline_color(maintenance)
    return "#6c757d" if maintenance.nil?
    maintenance.gantt_bar_color
  end
  
  # Safe date formatting
  def safe_date_format(date, format = "%b %d, %Y")
    return "N/A" if date.blank?
    date.strftime(format)
  end
  
  # Simple urgency badge class (just returns CSS class without "badge" prefix)
  def urgency_class(urgency)
    case urgency&.downcase
    when "emergency"
      "bg-danger"
    when "scheduled"
      "bg-warning text-dark"
    when "routine"
      "bg-primary"
    else
      "bg-secondary"
    end
  end
end