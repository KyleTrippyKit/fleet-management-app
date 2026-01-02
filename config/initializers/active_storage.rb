# config/initializers/active_storage.rb
Rails.application.config.active_storage.variant_processor = :vips

# Vips processing options
Vips.block(true)  # Enable thread safety

# Default variant options
Rails.application.config.active_storage.variant_options = {
  convert: 'jpg',
  saver: {
    quality: 80,
    strip: true  # Remove metadata
  }
}

# Common variant definitions
ActiveStorage::Variant::DEFAULT_TRANSFORMATIONS = {
  thumb: { resize_to_limit: [100, 100] },
  medium: { resize_to_limit: [300, 300] },
  large: { resize_to_limit: [800, 800] }
}