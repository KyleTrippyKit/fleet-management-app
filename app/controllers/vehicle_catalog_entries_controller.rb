# app/controllers/vehicle_catalog_entries_controller.rb
class VehicleCatalogEntriesController < ApplicationController
  before_action :authenticate_user!

  def index
    q = params[:q].to_s.strip
    entries = VehicleCatalogEntry.search(q).limit(25)
    render json: entries.map { |e|
      { id: e.id, make: e.make, model: e.model, label: e.label, vehicle_type: e.vehicle_type }
    }
  end

  def create
    entry = VehicleCatalogEntry.new(entry_params)
    if entry.save
      render json: { ok: true, id: entry.id, make: entry.make, model: entry.model, label: entry.label }
    else
      render json: { ok: false, errors: entry.errors.full_messages }, status: :unprocessable_entity
    end
  end

  private

  def entry_params
    params.require(:vehicle_catalog_entry).permit(:make, :model, :vehicle_type, :year_from, :year_to)
  end
end