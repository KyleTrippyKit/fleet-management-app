module VehiclesHelper
  def vehicle_image(vehicle)
    # Use main image if attached
    if vehicle.image.attached?
      vehicle.image
    # Use optional picture if main image is missing
    elsif vehicle.picture.attached?
      vehicle.picture
    else
      # Try to find placeholder by make (png, jpg, jpeg, webp)
      make_name = vehicle.make.to_s.downcase
      extensions = %w[png jpg jpeg webp]

      placeholder = extensions.map { |ext| "placeholders/#{make_name}.#{ext}" }.find do |path|
        Rails.root.join("app/assets/images/#{path}").exist?
      end

      # Return either the found placeholder or the default.png using asset_path
      asset_path(placeholder || "placeholders/default.png")
    end
  end
end
