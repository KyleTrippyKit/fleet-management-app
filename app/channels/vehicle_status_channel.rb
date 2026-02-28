class VehicleStatusChannel < ApplicationCable::Channel
  def subscribed
    vehicle = Vehicle.find(params[:vehicle_id])
    stream_for vehicle
  end

  def unsubscribed
    # Any cleanup needed when channel is unsubscribed
  end
end