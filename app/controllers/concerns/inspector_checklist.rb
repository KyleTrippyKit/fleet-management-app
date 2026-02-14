module InspectorChecklist
  extend ActiveSupport::Concern

  CHECK_ITEMS = [
    "Tyres", "Spare tyre", "Rims", "Wheel nuts", "Brakes", "Brake fluid", "Brake lights", "Headlights",
    "High beam", "Indicators", "Hazard lights", "Reverse lights", "Fog lights", "Horn", "Windshield",
    "Wipers", "Washer fluid", "Side mirrors", "Rear-view mirror", "Windows", "Door locks", "Seat belts",
    "Airbags indicator", "Dashboard warning lights", "Battery", "Alternator", "Starter", "Engine oil",
    "Coolant level", "Radiator", "Belts", "Hoses", "Transmission", "Clutch", "Steering", "Suspension",
    "Exhaust", "Muffler", "Fuel system", "Fuel cap", "Underbody", "Chassis", "License plate condition",
    "Registration sticker", "Fire extinguisher", "First aid kit", "Jack & tools", "Spare fuses", "Interior lights",
    "Air conditioning", "Heater", "Odometer", "GPS tracker", "Body condition", "Paint condition"
  ].freeze
end
