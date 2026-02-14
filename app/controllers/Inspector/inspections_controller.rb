module Inspector
  class InspectionsController < ApplicationController
    include InspectorChecklist

    before_action :authenticate_user!
    before_action :require_inspector_role!

    def create
      @vehicle = accessible_vehicles.find_by(id: inspection_params[:vehicle_id])

      unless @vehicle
        redirect_to inspector_home_path, alert: "Vehicle not found."
        return
      end

      if inspection_params[:checks].blank?
        redirect_to inspector_vehicle_path(@vehicle), alert: "Please complete all checklist items before submitting."
        return
      end

      Rails.cache.write(cache_key_for(@vehicle.id), submitted_payload, expires_in: 30.minutes)

      redirect_to submitted_inspector_inspections_path(vehicle_id: @vehicle.id), notice: "Inspection submitted successfully."
    end

    def submitted
      @vehicle = accessible_vehicles.find_by(id: params[:vehicle_id])

      unless @vehicle
        redirect_to inspector_home_path, alert: "Vehicle not found."
        return
      end

      unless Rails.cache.exist?(cache_key_for(@vehicle.id))
        redirect_to inspector_vehicle_path(@vehicle), alert: "No recent inspection submission found."
      end
    end

    private

    def inspection_params
      params.permit(:vehicle_id, :notes, checks: {})
    end

    def submitted_payload
      {
        inspector_id: current_user.id,
        submitted_at: Time.current,
        notes: inspection_params[:notes],
        checks: inspection_params[:checks]
      }
    end

    def accessible_vehicles
      if current_user.admin? || current_user.inspector_role?
        Vehicle
      else
        Vehicle.where(agency_id: current_user.agency_id)
      end
    end

    def cache_key_for(vehicle_id)
      "inspector:inspection_submission:user:#{current_user.id}:vehicle:#{vehicle_id}"
    end

    def require_inspector_role!
      return if current_user&.inspector_role? || current_user&.admin?

      redirect_to root_path, alert: "Inspector access only."
    end
  end
end