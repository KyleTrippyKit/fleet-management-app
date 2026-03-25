class WorkflowManagerNew
  attr_reader :inspection

  def initialize(inspection)
    @inspection = inspection
  end

  def intake_vehicle(params)
    puts "=== WORKFLOW_MANAGER_NEW ==="
    puts "params: #{params.inspect}"
    
    @inspection.update!(
      client_type: params[:client_type],
      payment_terms: params[:payment_terms],
      status: :pending_inspection,
      received_at: Time.current
    )
    
    puts "Inspection updated"
    
    log = ReceptionLog.create!(
      vehicle: @inspection.vehicle,
      user_id: Current.user.id,
      driver_name: params[:driver_name] || params[:customer_name] || "Walk-in Customer",
      visitor_name: params[:visitor_name] || params[:customer_name] || params[:driver_name] || "Walk-in Customer",
      check_in_time: Time.current,
      condition_status: 'pending'
    )
    
    puts "ReceptionLog created: #{log.id}"
    @inspection
  end
end
