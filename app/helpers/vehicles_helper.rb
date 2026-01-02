module VehiclesHelper
  # Primary method to get vehicle image - uses ActiveStorage with fallback to asset pipeline
  def vehicle_image(vehicle, variant: :medium)
    # Priority 1: Use ActiveStorage primary_photo if uploaded
    if vehicle.primary_photo.attached?
      case variant
      when :thumb
        vehicle.primary_photo.variant(resize_to_limit: [150, 100])
      when :medium
        vehicle.primary_photo.variant(resize_to_limit: [400, 300])
      when :large
        vehicle.primary_photo.variant(resize_to_limit: [800, 600])
      else
        vehicle.primary_photo
      end
    # Priority 2: Use asset pipeline placeholder images
    else
      vehicle_placeholder_image(vehicle, variant: variant)
    end
  end
  
  # Asset pipeline placeholder images (fallback)
  def vehicle_placeholder_image(vehicle, variant: :medium)
    # Map vehicles to your placeholder images
    image_mapping = {
      'Ford' => 'placeholders/Ford.webp',
      'Higer' => 'placeholders/Higer.jpg', 
      'Isuzu' => 'placeholders/Isuzu.jpg',
      'Nissan' => 'placeholders/Nissan.webp',
      'Suzuki' => 'placeholders/Suzuki.jpg',
      'Toyota' => vehicle.model == 'Hilux' ? 'placeholders/Toyota.jpeg' : 'placeholders/toyota.jpg'
    }
    
    # Find image by make, fallback to default
    image_path = image_mapping[vehicle.make] || 'placeholders/default.png'
    
    # Return the asset path
    asset_path(image_path)
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