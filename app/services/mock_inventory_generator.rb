# app/services/mock_inventory_generator.rb
class MockInventoryGenerator
  PRODUCT_CATEGORIES = [
    'Vehicle Parts',
    'Maintenance Services',
    'Fuel & Lubricants',
    'Tires & Wheels',
    'Batteries',
    'Accessories',
    'Tools & Equipment',
    'Cleaning Supplies'
  ]
  
  def self.generate_products_for_agency(agency_id, count: 50)
    products = []
    
    count.times do |i|
      category = PRODUCT_CATEGORIES.sample
      
      products << {
        sku: "SKU-#{agency_id}-#{i+1}",
        name: generate_product_name(category),
        description: generate_description(category),
        price: generate_price(category),
        stock_quantity: rand(0..100),
        reorder_level: rand(5..20),
        category: category,
        agency_id: agency_id,
        created_at: Time.current - rand(0..90).days,
        updated_at: Time.current
      }
    end
    
    products
  end
  
  def self.generate_product_name(category)
    prefixes = {
      'Vehicle Parts' => ['Engine', 'Brake', 'Suspension', 'Exhaust', 'Cooling'],
      'Maintenance Services' => ['Oil Change', 'Brake Service', 'Tire Rotation', 'Alignment', 'Tune-up'],
      'Fuel & Lubricants' => ['Premium', 'Regular', 'Diesel', 'Synthetic', 'Multi-grade'],
      'Tires & Wheels' => ['All-Season', 'Performance', 'Off-Road', 'Steel', 'Alloy']
    }
    
    suffixes = {
      'Vehicle Parts' => ['Kit', 'Assembly', 'System', 'Component', 'Part'],
      'Maintenance Services' => ['Service', 'Package', 'Check', 'Inspection'],
      'Fuel & Lubricants' => ['Oil', 'Fuel', 'Lubricant', 'Grease', 'Additive'],
      'Tires & Wheels' => ['Tire', 'Wheel', 'Rim', 'Tube']
    }
    
    prefix = prefixes[category]&.sample || 'Generic'
    suffix = suffixes[category]&.sample || 'Item'
    
    "#{prefix} #{suffix}"
  end
  
  def self.generate_description(category)
    descriptions = {
      'Vehicle Parts' => 'High-quality replacement part for Trinidad vehicles.',
      'Maintenance Services' => 'Professional service performed by certified technicians.',
      'Fuel & Lubricants' => 'Premium quality meeting Trinidad standards.',
      'Tires & Wheels' => 'Durable and reliable for Trinidad road conditions.'
    }
    
    descriptions[category] || 'Essential item for vehicle maintenance.'
  end
  
  def self.generate_price(category)
    base_prices = {
      'Vehicle Parts' => 50..500,
      'Maintenance Services' => 100..1000,
      'Fuel & Lubricants' => 20..200,
      'Tires & Wheels' => 100..800
    }
    
    rand(base_prices[category] || 10..100).to_f
  end
  
  def self.create_mock_sale(agency_id, item_count: rand(1..5))
    {
      transaction_id: "SALE-#{Time.current.strftime('%Y%m%d')}-#{SecureRandom.hex(4).upcase}",
      items: Array.new(item_count) do
        {
          product_id: rand(1..50),
          name: generate_product_name(PRODUCT_CATEGORIES.sample),
          quantity: rand(1..3),
          price: rand(20..500).to_f
        }
      end,
      subtotal: rand(100..1000).to_f,
      tax: rand(10..100).to_f,
      total: rand(110..1100).to_f,
      payment_method: ['cash', 'trinidad_debit_card', 'trinidad_credit_card', 'bank_transfer'].sample,
      timestamp: Time.current - rand(0..24).hours
    }
  end
end