module VehiclesHelper
  def vehicle_image(vehicle)
    if vehicle.image.attached?
      vehicle.image
    elsif vehicle.picture.attached?
      vehicle.picture
    else
      make_name = vehicle.make.to_s.downcase
      extensions = %w[png jpg jpeg webp]

      placeholder = extensions.map { |ext| "placeholders/#{make_name}.#{ext}" }.find do |path|
        Rails.root.join("app/assets/images/#{path}").exist?
      end

      asset_path(placeholder || "placeholders/default.png")
    end
  end
end
