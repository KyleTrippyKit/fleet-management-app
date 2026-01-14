module VehiclesHelper
  # Main method - simplified and fixed
  def vehicle_image(vehicle, variant: :medium, **html_options)
    if vehicle.primary_photo.attached?
      variant_size = case variant
        when :thumb then [300, 200]
        when :medium then [600, 400]
        when :large then [1200, 800]
        when :original then nil         # Keep original size
        else [600, 400]
      end
      
      begin
        image_tag(vehicle.primary_photo.variant(resize_to_limit: variant_size), **html_options)
      rescue => e
        Rails.logger.error "Active Storage error: #{e.message}"
        vehicle_placeholder_image(vehicle, html_options)
      end
    else
      vehicle_placeholder_image(vehicle, html_options)
    end
  end
  
  # Fixed: Accepts html_options as a regular parameter, not keyword args
  def vehicle_placeholder_image(vehicle, html_options = {})
    # Determine image name
    image_name = case vehicle.make.to_s.downcase
                 when 'ford' then 'Ford.webp'
                 when 'higer' then 'Higer.jpg'
                 when 'isuzu' then 'Isuzu.jpg'
                 when 'nissan' then 'Nissan.webp'
                 when 'suzuki' then 'Suzuki.jpg'
                 when 'toyota'
                   vehicle.model.to_s.downcase == 'hilux' ? 'Toyota.jpeg' : 'toyota.jpg'
                 else
                   'default.png'
                 end
    
    # Try multiple paths for Render compatibility
    begin
      # Try asset pipeline first (development)
      image_tag("placeholders/#{image_name}", html_options)
    rescue Sprockets::Rails::Helper::AssetNotFound
      # Try direct path (production/Render)
      image_tag("/placeholders/#{image_name}", html_options.merge(
        onerror: "this.onerror=null; this.style.display='none';"
      ))
    end
  end
  
  # URL version for places where you need just the URL
  def vehicle_image_url(vehicle, variant: :medium)
    if vehicle.primary_photo.attached?
      begin
        variant_size = case variant
          when :thumb then [150, 100]
          when :medium then [400, 300]
          when :large then [800, 600]
          else [400, 300]
        end
        vehicle.primary_photo.variant(resize_to_limit: variant_size)
      rescue => e
        Rails.logger.error "Active Storage error: #{e.message}"
        vehicle_placeholder_url(vehicle)
      end
    else
      vehicle_placeholder_url(vehicle)
    end
  end
  
  # Placeholder URL
  def vehicle_placeholder_url(vehicle)
    image_name = case vehicle.make.to_s.downcase
                 when 'ford' then 'Ford.webp'
                 when 'higer' then 'Higer.jpg'
                 when 'isuzu' then 'Isuzu.jpg'
                 when 'nissan' then 'Nissan.webp'
                 when 'suzuki' then 'Suzuki.jpg'
                 when 'toyota'
                   vehicle.model.to_s.downcase == 'hilux' ? 'Toyota.jpeg' : 'toyota.jpg'
                 else
                   'default.png'
                 end
    
    # Try asset path first, fall back to direct path
    begin
      asset_path("placeholders/#{image_name}")
    rescue Sprockets::Rails::Helper::AssetNotFound
      "/placeholders/#{image_name}"
    end
  end
  
  # Check if vehicle has uploaded photo
  def has_uploaded_photo?(vehicle)
    vehicle.primary_photo.attached?
  end
  
  # Gallery photo helpers
  def gallery_photos(vehicle)
    vehicle.gallery_photos.attached? ? vehicle.gallery_photos : []
  end
  
  def has_gallery_photos?(vehicle)
    vehicle.gallery_photos.attached?
  end
  
  # Simple mapping for service owner badges
  def service_owner_badge_class(owner)
    case owner.to_s
    when 'Police'
      'owner-police'
    when 'Fire Service'
      'owner-fire_service'
    when 'PTSC'
      'owner-ptsc'
    else
      'bg-secondary'
    end
  end
  
  # Vehicle status badge
  def vehicle_status_badge(vehicle)
    content_tag(:span, class: "badge #{vehicle.status_badge_class}") do
      vehicle.status_display
    end
  end
  
  # Photo upload info text
  def photo_upload_info(vehicle)
    if has_uploaded_photo?(vehicle)
      content_tag(:small, class: "text-success") do
        "✓ Custom photo uploaded"
      end
    else
      content_tag(:small, class: "text-muted") do
        "Using default placeholder based on vehicle make"
      end
    end
  end
  
  # Owner badge color for analytics page
  def owner_badge_color(owner)
    case owner.to_s
    when 'Police'
      'info'
    when 'Fire Service'
      'danger'
    when 'PTSC'
      'primary'
    else
      'secondary'
    end
  end
  
  # Utilization badge color for analytics page
  def utilization_badge_color(utilization)
    case utilization.to_f
    when 70..100
      'success'
    when 30...70
      'warning'
    else
      'danger'
    end
  end

  # =====================================================
  # MAINTENANCE HELPER METHODS - ADDED
  # =====================================================
  
  # Safe date formatting
  def format_date(date, format = "%b %d, %Y")
    date.present? ? date.strftime(format) : "Date not set"
  end

  # Safe date for tables
  def display_date(date, format = "%Y-%m-%d")
    date.present? ? date.strftime(format) : "-"
  end

  # Urgency badge helper
  def urgency_badge(maintenance)
    urgency = maintenance.urgency.presence || 'routine'
    label = urgency.titleize
    css_class = case urgency.downcase
                when 'emergency', 'high' then 'bg-danger'
                when 'scheduled', 'medium' then 'bg-warning text-dark'
                when 'routine', 'low' then 'bg-primary'
                else 'bg-secondary'
                end
    
    content_tag(:span, label, class: "badge #{css_class}")
  end

  # Owner badge class
  def owner_badge_class(owner)
    case owner.to_s
    when 'Police' then 'badge bg-info'
    when 'Fire Service' then 'badge bg-danger'
    when 'PTSC' then 'badge bg-primary'
    else 'badge bg-secondary'
    end
  end
  
  # Insurance status badge
  def insurance_status_badge(vehicle)
    content_tag(:span, 
                vehicle.insurance_status_display, 
                class: "badge #{vehicle.insurance_status_badge_class}")
  end

  # Insurance expiry info with tooltip
  def insurance_expiry_info(vehicle)
    return content_tag(:span, "No insurance data", class: "text-muted") unless vehicle.insurance_expiry_date.present?
    
    content_tag(:div, class: "insurance-expiry-info") do
      concat(content_tag(:span, vehicle.insurance_expiry_display))
      
      if vehicle.insurance_expired?
        concat(content_tag(:small, " OVERDUE", class: "text-danger ml-1"))
      elsif vehicle.insurance_expiring_soon?
        concat(content_tag(:small, " URGENT", class: "text-warning ml-1"))
      end
    end
  end

  # Insurance progress bar for dashboard
  def insurance_status_progress(vehicles)
    total = vehicles.count
    return "No vehicles" if total.zero?
    
    expired = vehicles.count(&:insurance_expired?)
    expiring = vehicles.count(&:insurance_expiring_soon?)
    active = vehicles.count - expired - expiring
    
    content_tag(:div, class: "insurance-progress") do
      concat(content_tag(:div, "", 
              class: "progress-bar bg-danger", 
              style: "width: #{((expired.to_f / total) * 100).round(1)}%",
              title: "#{expired} expired"))
      concat(content_tag(:div, "", 
              class: "progress-bar bg-warning", 
              style: "width: #{((expiring.to_f / total) * 100).round(1)}%",
              title: "#{expiring} expiring soon"))
      concat(content_tag(:div, "", 
              class: "progress-bar bg-success", 
              style: "width: #{((active.to_f / total) * 100).round(1)}%",
              title: "#{active} active"))
    end
  end
end