# frozen_string_literal: true

module Scanner
  class VehiclesController < ApplicationController
    before_action :authenticate_user!
    before_action :require_scanner!
    before_action :set_vehicle

    def show
      # scanner-only show (no driver/documents)
    end

    # ----------------------------
    # Scanner-only compound actions
    # ----------------------------

    def check_in_compound
      if @vehicle.in_compound?
        redirect_to scanner_vehicle_path(@vehicle), alert: "Already checked IN."
        return
      end

      @vehicle.update!(
        in_compound: true,
        checked_in_at: Time.current,
        checked_in_by_id: current_user.id
      )

      redirect_to scanner_vehicle_path(@vehicle),
                  notice: "Vehicle #{@vehicle.license_plate} checked IN to compound."
    end

    def check_out_compound
      unless @vehicle.in_compound?
        redirect_to scanner_vehicle_path(@vehicle), alert: "Cannot check OUT — vehicle is not checked IN."
        return
      end

      @vehicle.update!(
        in_compound: false,
        checked_out_at: Time.current,
        checked_out_by_id: current_user.id
      )

      redirect_to scanner_vehicle_path(@vehicle),
                  notice: "Vehicle #{@vehicle.license_plate} checked OUT of compound."
    end

    private

    def require_scanner!
      unless current_user&.admin? || current_user&.scanner_role?
        redirect_to scanner_home_path, alert: "Scanner access only."
      end
    end

    def set_vehicle
      @vehicle = Vehicle.includes(
        :agency,
        primary_photo_attachment: { blob: :variant_records },
        gallery_photos_attachments: { blob: :variant_records }
      ).find(params[:id])
    end
  end
end
