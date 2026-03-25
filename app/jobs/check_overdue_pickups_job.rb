class CheckOverduePickupsJob < ApplicationJob
  queue_as :default
  
  def perform
    # Scenario 26: Late pickup
    Inspection.overdue_pickup.find_each do |inspection|
      days_late = (Time.current.to_date - inspection.ready_for_pickup_at.to_date).to_i
      
      # Send reminder every 3 days
      if days_late % 3 == 0
        Notification.create!(
          title: "Vehicle waiting for pickup",
          message: "Your vehicle has been ready for #{days_late} days. Please arrange pickup to avoid storage fees.",
          link: "/customer/dashboard",
          user_id: inspection.client&.user_id
        )
      end
      
      # Apply storage fee after 7 days
      if days_late >= 7 && inspection.storage_fee_days == 0
        daily_rate = 50.00
        storage_fee = days_late * daily_rate
        
        Invoice.create!(
          inspection: inspection,
          vehicle: inspection.vehicle,
          amount: storage_fee,
          invoice_type: 'storage_fee',
          due_date: Time.current.to_date,
          status: 'pending',
          description: "Storage fee for #{days_late} days late pickup"
        )
        
        inspection.update!(storage_fee_days: days_late)
      end
    end
  end
end