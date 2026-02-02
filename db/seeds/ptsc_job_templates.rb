# db/seeds/ptsc_job_templates.rb
# Usage:
#   bin/rails runner db/seeds/ptsc_job_templates.rb

vmcott = Agency.find_by(code: "VMCOTT") || Agency.find_by(name: "VMCOTT")
ptsc   = Agency.find_by(code: "PTSC")   || Agency.find_by(name: "PTSC")

if vmcott.nil? || ptsc.nil?
  puts "❌ Missing agency. Need PTSC and VMCOTT agencies in DB."
  exit 1
end

# Decide where templates live:
# - If VMCOTT owns templates, set template_agency = vmcott
# - If PTSC should own its own templates, set template_agency = ptsc
template_agency = vmcott

templates = [
  {
    name: "Preventive Maintenance - Bus (Oil/Filters/Inspection)",
    category: "PM",
    description: "Standard bus PM: engine oil, oil filter, fuel filter check, air filter check, greasing, safety inspection.",
    standard_hours: 3.0,
    labor_rate_per_hour: 250.00,
    applies_to: [
      { make: "Hino",  model: "Blue Ribbon", year: 2016 },
      { make: "Hino",  model: "Blue Ribbon", year: 2017 },
      { make: "Isuzu", model: "NQR",         year: 2015 }
    ]
  },
  {
    name: "Brake Service - Heavy Vehicle",
    category: "Brakes",
    description: "Brake inspection, pads/shoes, drum/disc check, adjust, road test.",
    standard_hours: 4.0,
    labor_rate_per_hour: 250.00,
    applies_to: [
      { make: "Hino",  model: "Blue Ribbon", year: 2016 },
      { make: "Hino",  model: "Blue Ribbon", year: 2017 },
      { make: "Isuzu", model: "NQR",         year: 2015 }
    ]
  },
  {
    name: "Preventive Maintenance - Van (Oil/Filters/Inspection)",
    category: "PM",
    description: "Standard van PM: engine oil, oil filter, fuel filter check, safety inspection.",
    standard_hours: 2.0,
    labor_rate_per_hour: 250.00,
    applies_to: [
      { make: "Toyota", model: "Hiace", year: 2018 },
      { make: "Nissan", model: "NV350", year: 2019 }
    ]
  },
  {
    name: "Preventive Maintenance - Pickup (Oil/Filters/Inspection)",
    category: "PM",
    description: "Standard pickup PM: engine oil, filters, inspection, road test.",
    standard_hours: 2.0,
    labor_rate_per_hour: 250.00,
    applies_to: [
      { make: "Toyota", model: "Hilux",  year: 2020 },
      { make: "Nissan", model: "Navara", year: 2021 }
    ]
  },
  {
    name: "Preventive Maintenance - Car (Oil/Filters/Inspection)",
    category: "PM",
    description: "Standard car PM: engine oil, filters, inspection, road test.",
    standard_hours: 1.5,
    labor_rate_per_hour: 250.00,
    applies_to: [
      { make: "Toyota", model: "Corolla", year: 2017 },
      { make: "Nissan", model: "Sentra",  year: 2018 }
    ]
  }
]

created = 0
updated = 0
applications_created = 0

templates.each do |t|
  jt = JobTemplate.find_or_initialize_by(agency_id: template_agency.id, name: t[:name])
  jt.category = t[:category]
  jt.description = t[:description]
  jt.standard_hours = t[:standard_hours]
  jt.labor_rate_per_hour = t[:labor_rate_per_hour]
  jt.is_active = true

  if jt.new_record?
    jt.save!
    created += 1
  else
    if jt.changed?
      jt.save!
      updated += 1
    end
  end

  t[:applies_to].each do |app|
    a = JobTemplateVehicleApplication.find_or_initialize_by(
      job_template_id: jt.id,
      make: app[:make],
      model: app[:model],
      year: app[:year]
    )
    if a.new_record?
      a.save!
      applications_created += 1
    end
  end
end

puts "✅ PTSC Job Templates seeded under agency: #{template_agency.name}"
puts "Templates created: #{created}, updated: #{updated}, applications created: #{applications_created}"
puts "Total templates for #{template_agency.name}: #{JobTemplate.where(agency_id: template_agency.id).count}"
