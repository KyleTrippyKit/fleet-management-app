module VehiclesHelper
  def vehicle_image(vehicle, variant: :medium)
    # Try image attachment first (Active Storage)
    if vehicle.image.attached?
      variant_options = case variant
      when :thumb
        { resize_to_limit: [400, 300] }  # For index/cards
      when :medium
        { resize_to_limit: [800, 600] }  # For show pages
      when :large
        { resize_to_limit: [1200, 900] } # For full details
      else
        { resize_to_limit: [800, 600] }
      end
      
      # Return variant URL
      begin
        vehicle.image.variant(variant_options).processed.url
      rescue => e
        Rails.logger.error "Failed to process image variant: #{e.message}"
        vehicle.image
      end
    elsif vehicle.picture.attached?
      # Fallback to picture attribute (string/path)
      vehicle.picture
    else
      # Placeholder logic
      make_name = vehicle.make.to_s.downcase
      extensions = %w[png jpg jpeg webp]
      
      placeholder = extensions.map { |ext| "placeholders/#{make_name}.#{ext}" }.find do |path|
        Rails.root.join("app/assets/images/#{path}").exist?
      end
      
      asset_path(placeholder || "placeholders/default.png")
    end
  end
  
  # Helper to determine which variant to use based on context
  def image_variant_for_context(context = :index)
    case context
    when :index, :card
      :thumb
    when :show
      :medium
    when :full
      :large
    else
      :medium
    end
  end
end