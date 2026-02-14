module Inspector
  class InspectionsController < ApplicationController
    include InspectorChecklist
    before_action :authenticate_user!
    before_action :require_inspector_role!

    CHECK_OPTIONS = %w[Good Fair Needs\ Attention].freeze

    def create
      vehicle = Vehicle.find(params[:vehicle_id])
      checks = params[:checks].to_h
      required_items = CHECK_ITEMS

      unanswered = required_items.reject do |item|
        checks[item].present? && CHECK_OPTIONS.include?(checks[item])
      end

      if unanswered.any?
        redirect_to inspector_vehicle_path(vehicle), alert: "Please complete all inspection checks (#{unanswered.count} remaining)."
        return
      end

      redirect_to submitted_inspector_inspections_path(vehicle_id: vehicle.id), notice: "Inspection submitted successfully."
    end

    def submitted
      @vehicle = Vehicle.find(params[:vehicle_id])
    end

    private

    def require_inspector_role!
      return if current_user&.inspector_role? || current_user&.admin?

      redirect_to root_path, alert: "Inspector access only."
    end

  end
end
