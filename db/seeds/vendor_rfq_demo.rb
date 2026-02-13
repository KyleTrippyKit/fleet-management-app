# db/seeds/vendor_rfq_demo.rb
# Run: bin/rails db:seed_vendor_rfq_demo

vmcott_agency = Agency.find_by(code: "VMCOTT")
raise "Agency VMCOTT not found" unless vmcott_agency

user = User.where(agency_id: vmcott_agency.id).first || User.first
raise "No users found" unless user

suppliers = Supplier.where(is_active: true).order(:id).limit(3).to_a
raise "Need at least 3 active suppliers" if suppliers.size < 3

parts = Part.where(is_active: true).order(:id).limit(20).to_a
raise "Need parts in DB" if parts.empty?

3.times do |i|
  rfq = VendorRfq.create!(
    rfq_number: "VRFQ-DEMO-#{SecureRandom.hex(4).upcase}",
    status: "sent",
    sent_date: Date.current,
    due_date: Date.current + 7,
    notes: "Demo Vendor RFQ #{i + 1} for workflow testing",
    created_by: user,
    processing_agency: vmcott_agency
  )

  rfq_parts = parts.sample(3)

  rfq_parts.each_with_index do |p, idx|
    rfq.vendor_rfq_items.create!(
      part_id: p.id,
      description: "Demo item #{idx + 1} - #{p.name.presence || "Part ##{p.id}"}",
      quantity: (idx + 1) * 2,
      unit_of_measure: p.unit_of_measure.presence || "each"
    )
  end

  suppliers.each do |supplier|
    quotation = rfq.vendor_quotations.create!(
      supplier: supplier,
      status: "received",
      notes: "Demo quotation from #{supplier.name}",
      currency: "TTD"
    )

    rfq.vendor_rfq_items.each do |item|
      qty  = item.quantity.to_i
      unit = rand(50.0..250.0).round(2)
      total = (qty * unit).round(2)

      quotation.vendor_quotation_lines.create!(
        part_id: item.part_id,
        description: item.description,
        quantity: qty,
        unit_price: unit,
        total_price: total
      )
    end
  end

  puts "Created RFQ #{rfq.rfq_number} with #{rfq.vendor_rfq_items.count} items and #{rfq.vendor_quotations.count} quotations"
end
