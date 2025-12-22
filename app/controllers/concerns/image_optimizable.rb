module ImageOptimizable
  extend ActiveSupport::Concern
  
  included do
    before_save :optimize_attached_images
  end
  
  private
  
  def optimize_attached_images
    return unless self.class.column_names.include?('image')
    
    if image.attached? && image.new_record?
      begin
        # Process the image
        variant = image.variant(resize_to_limit: [1200, 900], convert: 'jpg', saver: { quality: 80 })
        variant.processed
      rescue => e
        Rails.logger.error "Failed to optimize image: #{e.message}"
      end
    end
  end
end