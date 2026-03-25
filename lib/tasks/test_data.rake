# lib/tasks/test_data.rake
namespace :test_data do
  desc "Generate test data for all scenarios"
  task generate: :environment do
    puts "Generating test data..."
    
    # Create test users
    roles = ['inspector', 'mechanic', 'procurement', 'workshop_supervisor', 'finance', 'security_gate_officer', 'inventory_manager']
    roles.each do |role|
      User.find_or_create_by!(email: "#{role}@test.com") do |u|
        u.password = 'password123'
        u.password_confirmation = 'password123'
        u.role = role
        u.name = role.humanize
        u.agency = Agency.first || Agency.create!(name: "VMCOTT", code: "VMCOTT")
      end
    end
    
    # Create test vehicles
    5.times do |i|
      Vehicle.find_or_create_by!(license_plate: "TEST-#{i+1}") do |v|
        v.make = ["Toyota", "Honda", "Mitsubishi", "Nissan", "Ford"].sample
        v.model = ["Corolla", "Civic", "Lancer", "Sunny", "Focus"].sample
        v.year_of_manufacture = rand(2015..2024)
        v.agency = Agency.first
        v.status = 'active'
      end
    end
    
    puts "Test data generated successfully!"
  end
  
  desc "Create a full test workflow for demonstration"
  task demo_workflow: :environment do
    vehicle = Vehicle.first
    inspector = User.find_by(role: 'inspector')
    
    inspection = Inspection.create!(
      vehicle: vehicle,
      inspector: inspector,
      client_type: 'walkin',
      payment_terms: 'cash',
      status: 'pending_inspection'
    )
    
    puts "Created inspection ##{inspection.id} for #{vehicle.license_plate}"
    
    workflow = WorkflowManager.new(inspection)
    workflow.intake_vehicle({
      client_type: 'walkin',
      payment_terms: 'cash',
      customer_name: 'Demo Customer',
      expected_pickup_date: 3.days.from_now
    })
    
    puts "Phase 1: Vehicle intake complete"
    
    workflow.perform_inspection([
      { description: "Brake pads replacement", labor_cost: 85.00, severity: 'major', priority: 'high' }
    ])
    
    puts "Phase 2: Inspection complete"
    
    part = Part.create!(
      name: "Brake Pads",
      part_number: "BP-DEMO-001",
      current_stock: 5,
      price: 45.00
    )
    
    job = inspection.inspection_jobs.first
    workflow.mechanic_review(job.id, {
      description: "Replace worn brake pads",
      labor_cost: 85.00,
      parts_requested: [{ part: part, quantity: 2 }]
    })
    
    puts "Phase 3: Mechanic review complete"
    
    puts "Demo workflow ready! Visit /vmcott/inspections/#{inspection.id} to continue"
  end
end