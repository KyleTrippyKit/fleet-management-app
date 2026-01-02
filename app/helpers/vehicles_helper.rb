module VehiclesHelper
  # Main method - simplified and fixed
  def vehicle_image(vehicle, variant: :medium, **html_options)
    if vehicle.primary_photo.attached?
      variant_size = case variant
        when :thumb then [150, 100]
        when :medium then [400, 300]
        when :large then [800, 600]
        else [400, 300]
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
    case owner
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
  
  # Helper for utilization color classes
  def utilization_class(vehicle)
    percent = vehicle.utilization_percent.to_i rescue 0

    case percent
    when 0..29
      "utilization-low"
    when 30..69
      "utilization-medium"
    else
      "utilization-high"
    end
  end
  
  # Display utilization percentage with color
  def utilization_display(utilization)
    content_tag(:span, class: "badge bg-#{utilization_color(utilization)}") do
      "#{utilization.round(1)}%" if utilization.present?
    end
  end
  
  # Utilization color helper (compatible with controller method)
  def utilization_color(utilization)
    case utilization.to_f
    when 0..30 then 'danger'
    when 31..70 then 'warning'
    else 'success'
    end
  end
  
  # Owner color helper (compatible with controller method)
  def owner_color(owner)
    case owner
    when 'PTSC' then 'primary'
    when 'Police' then 'danger'
    when 'Fire Service' then 'warning'
    else 'secondary'
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
end