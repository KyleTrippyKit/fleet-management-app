# app/helpers/inventory_helper.rb
module InventoryHelper
  def stock_badge_color(current_stock, minimum_stock)
    if current_stock.zero?
      'danger'  # red for out of stock
    elsif current_stock <= minimum_stock
      'warning' # yellow for low stock
    else
      'success' # green for in stock
    end
  end
  
  def stock_status_text(current_stock, minimum_stock)
    if current_stock.zero?
      'Out of Stock'
    elsif current_stock <= minimum_stock
      'Low Stock'
    else
      'In Stock'
    end
  end
  
  def stock_icon(current_stock, minimum_stock)
    if current_stock.zero?
      'bi-x-circle text-danger'
    elsif current_stock <= minimum_stock
      'bi-exclamation-triangle text-warning'
    else
      'bi-check-circle text-success'
    end
  end
  
  def days_of_supply_badge(days)
    if days == Float::INFINITY || days > 60
      'success'
    elsif days > 30
      'info'
    elsif days > 14
      'warning'
    else
      'danger'
    end
  end
  
  def format_days_of_supply(days)
    if days == Float::INFINITY
      '∞'
    elsif days > 365
      "#{(days / 365.0).round(1)} years"
    elsif days > 60
      "#{(days / 30.0).round(1)} months"
    else
      "#{days.round(0)} days"
    end
  end
  
  def reorder_status_badge(part)
    if part.current_stock <= part.minimum_stock
      'danger'
    elsif part.current_stock <= part.reorder_point
      'warning'
    else
      'success'
    end
  end
  
  def reorder_status_text(part)
    if part.current_stock <= part.minimum_stock
      'Needs Immediate Reorder'
    elsif part.current_stock <= part.reorder_point
      'Needs Reorder Soon'
    else
      'Adequate Stock'
    end
  end
end