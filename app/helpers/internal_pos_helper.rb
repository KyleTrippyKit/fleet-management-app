# app/helpers/internal_pos_helper.rb
module InternalPosHelper
  def display_vehicle_info(job)
    vehicle = job.vehicle || job.purchase_order&.vehicle
    if vehicle
      "#{vehicle.make} #{vehicle.model} - #{vehicle.license_plate}"
    else
      "Vehicle information unavailable"
    end
  end
  
  def stock_status_badge(item)
    return "" unless item.part.present?
    
    stock_class = item.part.current_stock >= item.quantity ? 'success' : 'danger'
    stock_text = item.part.current_stock >= item.quantity ? 'In Stock' : 'Low Stock'
    
    content_tag(:span, class: "badge bg-#{stock_class}") do
      "#{item.part.current_stock} in stock".html_safe
    end
  end
end