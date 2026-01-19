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

  # Helper methods for analytics page
  
  # Returns the color class for owner badges
  def owner_badge_color(owner)
    case owner.to_s
    when 'Police' then 'danger'
    when 'Fire Service' then 'warning'
    when 'PTSC' then 'primary'
    else 'secondary'
    end
  end
  
  # Returns the full badge class for owners
  def owner_badge_class(owner)
    "bg-#{owner_badge_color(owner)}"
  end
  
  # Returns the color class for utilization badges
  def utilization_badge_color(utilization)
    case utilization.to_f
    when 0..30 then 'danger'
    when 31..70 then 'warning'
    else 'success'
    end
  end
  
  # Returns the full badge class for utilization
  def utilization_badge_class(utilization)
    "bg-#{utilization_badge_color(utilization)}"
  end
  
  # Display utilization percentage with color
  def utilization_display(utilization)
    return content_tag(:span, "N/A", class: "badge bg-secondary") if utilization.blank?
    
    content_tag(:span, class: "badge #{utilization_badge_class(utilization)}") do
      "#{utilization.round(1)}%"
    end
  end
  
  # NEW: Helper for payment audit action icons
  def audit_action_icon(action)
    case action.to_s
    when 'initiated'
      'fa-play-circle'
    when 'authorized'
      'fa-shield-alt'
    when 'processed'
      'fa-cogs'
    when 'completed'
      'fa-check-circle'
    when 'failed'
      'fa-exclamation-circle'
    when 'retried'
      'fa-redo'
    when 'refunded'
      'fa-undo'
    when 'disputed'
      'fa-exclamation-triangle'
    else
      'fa-info-circle'
    end
  end

  # ========================
  # POS SYSTEM HELPERS - NEW
  # ========================

  # Get current agency (cached for performance)
  def current_agency
    @current_agency ||= current_user&.agency
  end

  # Agency-specific POS path helper
  def agency_pos_path(agency_code = nil)
    agency_code ||= current_agency&.code&.downcase
    return unless agency_code
    
    case agency_code.downcase
    when 'ptsc'
      ptsc_pos_transactions_path
    when 'ttps'
      ttps_pos_transactions_path
    when 'ttdf'
      ttdf_pos_transactions_path
    when 'vmcott'
      vmcott_pos_transactions_path
    else
      pos_transactions_path
    end
  end

  # Agency-specific POS dashboard path
  def agency_pos_dashboard_path(agency_code = nil)
    agency_code ||= current_agency&.code&.downcase
    return unless agency_code
    
    case agency_code.downcase
    when 'ptsc'
      dashboard_pos_transactions_path(agency: 'ptsc')
    when 'ttps'
      dashboard_pos_transactions_path(agency: 'ttps')
    when 'ttdf'
      dashboard_pos_transactions_path(agency: 'ttdf')
    when 'vmcott'
      dashboard_pos_transactions_path(agency: 'vmcott')
    else
      dashboard_pos_transactions_path
    end
  end

  # POS status badge with color coding
  def pos_status_badge(status)
    color_class = case status.to_sym
                  when :completed then 'success'
                  when :pending then 'warning'
                  when :voided then 'danger'
                  when :refunded then 'info'
                  else 'secondary'
                  end
    
    content_tag(:span, status.to_s.humanize, class: "badge bg-#{color_class}")
  end

  # POS payment type badge with icon
  def pos_payment_type_badge(payment_type)
    icon_class = case payment_type.to_sym
                 when :card then 'fa-credit-card'
                 when :cash then 'fa-money-bill'
                 when :mobile_money then 'fa-mobile-alt'
                 when :bank_transfer then 'fa-university'
                 else 'fa-wallet'
                 end
    
    content_tag(:span, class: "badge bg-light text-dark") do
      content_tag(:i, '', class: "fas #{icon_class} me-1") + payment_type.to_s.humanize
    end
  end

  # Generate agency-specific POS transaction ID
  def generate_pos_transaction_id(agency_code = nil)
    agency_code ||= current_agency&.code || 'GEN'
    timestamp = Time.now.strftime('%Y%m%d%H%M%S')
    random = SecureRandom.hex(4).upcase
    "POS-#{agency_code}-#{timestamp}-#{random}"
  end

  # Agency-specific POS color themes
  def pos_agency_theme(agency_code = nil)
    agency_code ||= current_agency&.code&.downcase
    
    case agency_code.to_s.downcase
    when 'ptsc'
      { bg: 'bg-primary', text: 'text-primary', border: 'border-primary' }
    when 'ttps'
      { bg: 'bg-danger', text: 'text-danger', border: 'border-danger' }
    when 'ttdf'
      { bg: 'bg-success', text: 'text-success', border: 'border-success' }
    when 'vmcott'
      { bg: 'bg-warning', text: 'text-warning', border: 'border-warning' }
    else
      { bg: 'bg-secondary', text: 'text-secondary', border: 'border-secondary' }
    end
  end

  # Agency-specific POS header
  def pos_agency_header(agency_code = nil)
    agency_code ||= current_agency&.code&.downcase
    
    theme = pos_agency_theme(agency_code)
    
    content_tag(:div, class: "card mb-4 #{theme[:border]} border-2") do
      content_tag(:div, class: "card-header #{theme[:bg]} text-white d-flex justify-content-between align-items-center") do
        content_tag(:h5, class: "mb-0") do
          agency_name = case agency_code.to_s.downcase
                       when 'ptsc' then 'Public Transport Service Corporation (PTSC)'
                       when 'ttps' then 'Trinidad and Tobago Police Service (TTPS)'
                       when 'ttdf' then 'Trinidad and Tobago Defence Force (TTDF)'
                       when 'vmcott' then 'Fire Service (VMCOTT)'
                       else 'General POS'
                       end
          "#{agency_name} Point of Sale"
        end + content_tag(:span, agency_code.to_s.upcase, class: "badge bg-light text-dark fs-6")
      end
    end
  end

  # Agency-specific POS items/products
  def agency_pos_items(agency_code = nil)
    agency_code ||= current_agency&.code&.downcase
    
    case agency_code.to_s.downcase
    when 'ptsc'
      [
        { name: 'Bus Ticket (Single Ride)', price: 7.00, category: 'Transport' },
        { name: 'Day Pass', price: 25.00, category: 'Transport' },
        { name: 'Weekly Pass', price: 120.00, category: 'Transport' },
        { name: 'Monthly Pass', price: 450.00, category: 'Transport' },
        { name: 'Senior Citizen Pass', price: 200.00, category: 'Transport' },
        { name: 'Student Pass', price: 300.00, category: 'Transport' }
      ]
    when 'ttps'
      [
        { name: 'Traffic Fine - Speeding', price: 500.00, category: 'Fines' },
        { name: 'Traffic Fine - Parking', price: 200.00, category: 'Fines' },
        { name: 'Driver\'s License Renewal', price: 300.00, category: 'Permits' },
        { name: 'Vehicle Registration', price: 150.00, category: 'Permits' },
        { name: 'Police Clearance', price: 100.00, category: 'Services' },
        { name: 'Firearm Permit Fee', price: 1000.00, category: 'Permits' }
      ]
    when 'ttdf'
      [
        { name: 'Port Entry Fee', price: 250.00, category: 'Port Fees' },
        { name: 'Shipping Documentation', price: 150.00, category: 'Services' },
        { name: 'Customs Clearance', price: 500.00, category: 'Services' },
        { name: 'Security Clearance', price: 300.00, category: 'Services' },
        { name: 'Military ID Renewal', price: 50.00, category: 'Permits' },
        { name: 'Base Access Pass', price: 100.00, category: 'Permits' }
      ]
    when 'vmcott'
      [
        { name: 'Fire Inspection Fee', price: 500.00, category: 'Inspections' },
        { name: 'Fire Safety Certificate', price: 300.00, category: 'Certificates' },
        { name: 'Fire Extinguisher Refill', price: 150.00, category: 'Services' },
        { name: 'Fire Drill Certification', price: 800.00, category: 'Services' },
        { name: 'Emergency Response Fee', price: 1000.00, category: 'Services' },
        { name: 'Fire Permit Renewal', price: 200.00, category: 'Permits' }
      ]
    else
      [
        { name: 'General Service Fee', price: 100.00, category: 'Services' },
        { name: 'Processing Fee', price: 50.00, category: 'Fees' },
        { name: 'Administration Fee', price: 75.00, category: 'Fees' }
      ]
    end
  end

  # Check if user has access to specific agency POS
  def can_access_agency_pos?(agency_code)
    return false unless current_user
    return true if current_user.admin? # Admins can access all
    
    current_agency&.code&.downcase == agency_code.to_s.downcase
  end

  # Agency POS navigation tabs
  def agency_pos_tabs
    agencies = [
      { code: 'ptsc', name: 'PTSC', path: ptsc_pos_transactions_path },
      { code: 'ttps', name: 'TTPS', path: ttps_pos_transactions_path },
      { code: 'ttdf', name: 'TTDF', path: ttdf_pos_transactions_path },
      { code: 'vmcott', name: 'Fire Service', path: vmcott_pos_transactions_path }
    ]
    
    content_tag(:div, class: 'd-flex mb-4') do
      agencies.map do |agency|
        active = current_agency&.code&.downcase == agency[:code]
        theme = pos_agency_theme(agency[:code])
        
        if can_access_agency_pos?(agency[:code])
          link_to agency[:path], class: "btn #{active ? theme[:bg] + ' text-white' : 'btn-outline-' + theme[:text].gsub('text-', '')} me-2" do
            agency[:name]
          end
        end
      end.compact.join.html_safe
    end
  end

  # Quick POS transaction summary - FIXED: Now calls transaction.agency_name which exists
  def pos_transaction_summary(transaction)
    content_tag(:div, class: 'card') do
      content_tag(:div, class: 'card-body') do
        content_tag(:div, class: 'row') do
          content_tag(:div, class: 'col-md-6') do
            content_tag(:p) do
              content_tag(:strong, 'Transaction ID: ') + transaction.transaction_id
            end +
            content_tag(:p) do
              content_tag(:strong, 'Date: ') + format_date(transaction.created_at, format: :datetime)
            end +
            content_tag(:p) do
              content_tag(:strong, 'Amount: ') + format_currency(transaction.amount)
            end
          end +
          content_tag(:div, class: 'col-md-6') do
            content_tag(:p) do
              content_tag(:strong, 'Status: ') + pos_status_badge(transaction.status)
            end +
            content_tag(:p) do
              content_tag(:strong, 'Payment Type: ') + pos_payment_type_badge(transaction.payment_type)
            end +
            content_tag(:p) do
              # FIXED: transaction.agency_name now exists after adding the method to the model
              content_tag(:strong, 'Agency: ') + transaction.agency_name
            end
          end
        end
      end
    end
  end
end