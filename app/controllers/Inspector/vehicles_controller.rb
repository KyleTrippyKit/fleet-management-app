module Inspector
  class VehiclesController < ApplicationController
    include InspectorChecklist
    before_action :authenticate_user!
    before_action :require_inspector_role!
    before_action :set_vehicle, only: :show

    def lookup
      plate = params[:license_plate].to_s.upcase.gsub(/[^A-Z0-9]/, "")

      if plate.blank?
        redirect_to inspector_home_path, alert: "Please enter a license plate."
        return
      end

      scope = current_user&.admin? || current_user&.inspector_role? ? Vehicle.all : Vehicle.where(agency_id: current_user.agency_id)

      vehicle = scope.find_by(
        "upper(regexp_replace(license_plate, '[^A-Za-z0-9]', '', 'g')) = ?",
        plate
      )

      if vehicle
        redirect_to inspector_vehicle_path(vehicle)
      else
        redirect_to inspector_home_path, alert: "No vehicle found for plate: #{plate}"
      end
    end

    def show
      @inspection_items = CHECK_ITEMS
    end

    private

    def set_vehicle
      @vehicle = Vehicle.includes(:agency).find(params[:id])
    end

    def require_inspector_role!
      return if current_user&.inspector_role? || current_user&.admin?

      redirect_to root_path, alert: "Inspector access only."
    end

  end
end
