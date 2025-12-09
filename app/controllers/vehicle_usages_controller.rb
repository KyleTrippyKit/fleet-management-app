class VehicleUsagesController < ApplicationController
  before_action :set_vehicle, only: [:new, :create]

  def index
    # DATE RANGE
    from = params[:from].present? ? Date.parse(params[:from]) : 30.days.ago.to_date
    to   = params[:to].present?   ? Date.parse(params[:to])   : Date.today

    # OWNER FILTER
    owner = params[:owner].present? && params[:owner] != "All" ? params[:owner] : nil

    @vehicles = Vehicle.all
    @vehicles = @vehicles.where(service_owner: owner) if owner

    # TABLE DATA
    @vehicle_usages = []

    # CHART DATA
    @chart_data_distance = {}   # bar
    @chart_data_hours    = {}   # bar
    @chart_data_util     = {}   # bar
    @chart_data_daily    = []   # line (array of series)

    # --------------------------------------------------------------
    # PROCESS EACH VEHICLE
    # --------------------------------------------------------------
    @vehicles.each do |vehicle|
      trips = vehicle.trips.where(start_time: from.beginning_of_day..to.end_of_day)

      distance_sum = trips.sum(:distance_km).to_f
      hours_sum    = trips.sum(:duration_hours).to_f
      trip_count   = trips.count

      # DAILY UTILIZATION (for line chart)
      daily_usage = (from..to).map do |day|
        day_trips = trips.where(start_time: day.beginning_of_day..day.end_of_day)
        hours = day_trips.sum(:duration_hours).to_f
        percent = ((hours / 24.0) * 100).round(1)

        { date: day, percent: percent }
      end

      # OVERALL UTILIZATION
      total_days = (to - from + 1).to_i
      utilization = if total_days > 0
        ((hours_sum / (total_days * 24.0)) * 100).round(1)
      else
        0
      end

      # TABLE ROW
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

      # LABEL FOR ALL CHARTS
      label = "#{vehicle.make} #{vehicle.model} (#{vehicle.registration_number})"

      # --------------------------------------------------------------
      # BAR CHART DATA
      # --------------------------------------------------------------
      @chart_data_distance[label] = distance_sum
      @chart_data_hours[label]    = hours_sum
      @chart_data_util[label]     = utilization

      # --------------------------------------------------------------
      # DAILY LINE CHART DATA (Chartkick correct format)
      # MUST be: [{ name: "...", data: {"2025-12-01" => 10, ...} }]
      # --------------------------------------------------------------
      @chart_data_daily << {
        name: label,
        data: daily_usage.map { |d| [d[:date].strftime("%Y-%m-%d"), d[:percent]] }.to_h
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
