class VehicleDocumentsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_vehicle, only: [:create]
  before_action :set_document, only: [:destroy]

  def create
    @document = @vehicle.vehicle_documents.new(document_params)

    if @document.save
      redirect_to full_details_vehicle_path(@vehicle), notice: "Document uploaded successfully."
    else
      redirect_to full_details_vehicle_path(@vehicle), alert: "Failed to upload document."
    end
  end

  def destroy
    vehicle = @document.vehicle
    @document.destroy
    redirect_to full_details_vehicle_path(vehicle), notice: "Document deleted successfully."
  end

  private

  def set_vehicle
    @vehicle = Vehicle.find(params[:vehicle_id])
  end

  def set_document
    @document = VehicleDocument.find(params[:id])
  end

  def document_params
    params.require(:vehicle_document).permit(:doc_type, :expires_on, :file)
  end
end
