module Inspector
  class VehiclesController < ApplicationController
    include InspectorChecklist
    before_action :authenticate_user!
    before_action :require_inspector_role!
    before_action :set_vehicle, only: :show

    def lookup
      plate = normalize_plate(params[:license_plate])

      if plate.blank?
        redirect_to inspector_home_path, alert: "Please enter a license plate."
        return
      end

      scope = current_user&.admin? || current_user&.inspector_role? ? Vehicle.all : Vehicle.where(agency_id: current_user.agency_id)

      vehicle = scope.find_by(
        "upper(regexp_replace(coalesce(license_plate, ''), '[^A-Za-z0-9]', '', 'g')) = :plate OR upper(regexp_replace(coalesce(registration_number, ''), '[^A-Za-z0-9]', '', 'g')) = :plate",
        plate: plate

      )

      if vehicle
        redirect_to inspector_vehicle_path(vehicle)
      else
        redirect_to inspector_home_path, alert: "No vehicle found for plate: #{plate}"
      end
    end

    def show
      @inspection_items = CHECK_ITEMS

        respond_to do |format|
        format.html
        format.turbo_stream { render :show, formats: [:html] }
      end
    end

    private

    def normalize_plate(raw_plate)
      raw_plate.to_s.upcase.gsub(/[^A-Z0-9]/, "")
    end
    
    def set_vehicle
      scope =
        if current_user.admin? || current_user.inspector_role?
          Vehicle
        else
          Vehicle.where(agency_id: current_user.agency_id)
        end

      @vehicle = scope.includes(:agency).find_by(id: params[:id])

      return if @vehicle

      redirect_to inspector_home_path, alert: "Vehicle not found."
    end


    def require_inspector_role!
      return if current_user&.inspector_role? || current_user&.admin?

      redirect_to root_path, alert: "Inspector access only."
    end

  end
end
