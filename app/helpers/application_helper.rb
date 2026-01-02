module ApplicationHelper
  # Generate a sortable link for table headers with Turbo support
  def sortable(column, title = nil)
    title ||= column.titleize

    # Determine the direction for the next click
    direction = (column == params[:sort] && params[:direction] == "asc") ? "desc" : "asc"

    # Add visual indicator if this column is currently sorted
    arrow = if column == params[:sort]
              params[:direction] == "asc" ? " ▲" : " ▼"
            else
              ""
            end

    # Merge current search query and notes filter with sorting params, keep Turbo frame for live updates
    link_to "#{title}#{arrow}".html_safe,
            params.permit(:query, :notes, :page).merge(sort: column, direction: direction),
            data: { turbo_frame: "drivers_table" }
  end

  # Sortable helper for trips table on driver show page
  def sortable_trip(column, title = nil)
    title ||= column.titleize
    direction = (column == params[:trip_sort] && params[:trip_direction] == "asc") ? "desc" : "asc"
    arrow = (column == params[:trip_sort]) ? (params[:trip_direction] == "asc" ? " ▲" : " ▼") : ""
    link_to "#{title}#{arrow}".html_safe,
            params.permit(:trip_page).merge(trip_sort: column, trip_direction: direction),
            data: { turbo_frame: "driver_trips" }
  end
  
  # Format vehicle display name with optional badge
  def vehicle_display_name(vehicle, with_badge: false)
    name = "#{vehicle.make} #{vehicle.model}"
    
    if with_badge && vehicle.license_plate.present?
      name += content_tag(:span, vehicle.license_plate, class: "badge bg-secondary ms-2")
    end
    
    name.html_safe
  end
  
  # Helper for showing formatted dates
  def format_date(date, format: :short)
    return "N/A" if date.blank?
    
    case format
    when :short
      date.strftime("%b %d, %Y")
    when :long
      date.strftime("%B %d, %Y")
    when :datetime
      date.strftime("%b %d, %Y %I:%M %p")
    else
      date.to_s
    end
  end
  
  # Helper for showing currency values
  def format_currency(amount)
    return "N/A" if amount.blank?
    number_to_currency(amount, unit: "$")
  end
  
  # Helper for showing distance values
  def format_distance(km, precision: 1)
    return "N/A" if km.blank?
    number_with_precision(km, precision: precision, delimiter: ',') + " km"
  end
  
  # Helper for showing duration values
  def format_duration(hours)
    return "N/A" if hours.blank?
    
    if hours < 1
      minutes = (hours * 60).round
      "#{minutes} min"
    elsif hours < 24
      "#{hours.round(1)} hours"
    else
      days = (hours / 24).round(1)
      "#{days} days"
    end
  end
  
  # Active class for navigation links
  def active_class(path)
    current_page?(path) ? 'active' : ''
  end
  
  # Flash message styling
  def flash_class(level)
    case level.to_sym
    when :notice then "alert alert-info"
    when :success then "alert alert-success"
    when :error then "alert alert-danger"
    when :alert then "alert alert-warning"
    else "alert alert-#{level}"
    end
  end
end