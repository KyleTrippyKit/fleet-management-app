class VehicleUsagesController < ApplicationController
  before_action :set_vehicle, only: [:new, :create]

  def index
    # ---------------------------
    # DATE RANGE
    # ---------------------------
    from = params[:from].present? ? Date.parse(params[:from]) : 30.days.ago.to_date
    to   = params[:to].present?   ? Date.parse(params[:to])   : Date.today

    # ---------------------------
    # OWNER FILTER
    # ---------------------------
    owner = params[:owner].present? && params[:owner] != "All" ? params[:owner] : nil

    @vehicles = Vehicle.all
    @vehicles = @vehicles.where(service_owner: owner) if owner

    # ---------------------------
    # Initialize chart and table data
    # ---------------------------
    @vehicle_usages = []
    @chart_data_distance = {}   # For Chartkick
    @chart_data_hours    = {}   # For Chartkick
    @chart_data_util     = {}   # For Chartkick
    @chart_data_daily    = []   # For Chartkick line chart
    @chart_data          = []   # For Stimulus chart_controller.js

    # ---------------------------
    # Process each vehicle
    # ---------------------------
    @vehicles.each do |vehicle|
      trips = vehicle.trips.where(start_time: from.beginning_of_day..to.end_of_day)

      distance_sum = trips.sum(:distance_km).to_f
      hours_sum    = trips.sum(:duration_hours).to_f
      trip_count   = trips.count

      # Daily utilization for line chart
      daily_usage = (from..to).map do |day|
        day_trips = trips.where(start_time: day.beginning_of_day..day.end_of_day)
        hours = day_trips.sum(:duration_hours).to_f
        percent = ((hours / 24.0) * 100).round(1)
        { date: day, percent: percent }
      end

      # Overall utilization
      total_days = (to - from + 1).to_i
      utilization = total_days > 0 ? ((hours_sum / (total_days * 24.0)) * 100).round(1) : 0

      # ---------------------------
      # Add table row
      # ---------------------------
      @vehicle_usages << {
        name: "#{vehicle.make} #{vehicle.model}",
        registration_number: vehicle.registration_number,
        service_owner: vehicle.service_owner,
        trip_count: trip_count,
        distance_km: distance_sum,
        hours_plied: hours_sum,
        utilization: utilization,
        daily_usage: daily_usage
      }

      label = "#{vehicle.make} #{vehicle.model} (#{vehicle.registration_number})"

      # ---------------------------
      # Add chart data for Chartkick
      # ---------------------------
      @chart_data_distance[label] = distance_sum
      @chart_data_hours[label]    = hours_sum
      @chart_data_util[label]     = utilization
      @chart_data_daily << { name: label, data: daily_usage.map { |d| [d[:date].strftime("%Y-%m-%d"), d[:percent]] }.to_h }

      # ---------------------------
      # Add chart data for Stimulus chart_controller.js
      # ---------------------------
      @chart_data << {
        registration_number: label,
        daily_usage: daily_usage,
        trip_count: trip_count,
        distance_km: distance_sum,
        hours_plied: hours_sum
      }
    end
  end

  def new
    @vehicle_usage = @vehicle.trips.new
  end

  def create
    @vehicle_usage = @vehicle.trips.new(trip_params)
    if @vehicle_usage.save
      redirect_to vehicle_vehicle_usages_path(@vehicle), notice: "Trip added."
    else
      render :new
    end
  end

  private

  def set_vehicle
    @vehicle = Vehicle.find_by(id: params[:vehicle_id])
  end

  def trip_params
    params.require(:trip).permit(:start_time, :end_time, :distance_km, :duration_hours, :driver_id)
  end
end
