class MaintenancesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_vehicle, only: [:index, :new, :create, :show, :edit, :update, :destroy, :gantt]
  before_action :set_maintenance, only: [:show, :edit, :update, :destroy]

  # GET /vehicles/:vehicle_id/maintenances
  def index
    if @vehicle.present?
      @maintenances = @vehicle.maintenances.order(
        Arel.sql("
          CASE status 
            WHEN 'Pending' THEN 0 
            WHEN 'Completed' THEN 1 
            ELSE 2 
          END ASC,
          date ASC
        ")
      )
    else
      @maintenances = Maintenance
        .includes(:vehicle)
        .order(Arel.sql("
          CASE status 
            WHEN 'Pending' THEN 0 
            WHEN 'Completed' THEN 1 
            ELSE 2 
          END ASC,
          date ASC
        "))
    end
  end

  # GET /vehicles/:vehicle_id/maintenances/gantt
  def gantt
    # Ensure @maintenances is never nil
    @maintenances = if @vehicle.present?
                      @vehicle.maintenances.order(:date)
                    else
                      Maintenance.all.order(:date)
                    end
  end

  # GET /vehicles/:vehicle_id/maintenances/:id
  def show; end

  # GET /vehicles/:vehicle_id/maintenances/new
  def new
    @maintenance = @vehicle.maintenances.new
    @maintenance.mileage ||= @vehicle.mileage
  end

  # POST /vehicles/:vehicle_id/maintenances
  def create
    @maintenance = @vehicle.maintenances.new(maintenance_params)
    if @maintenance.save
      MaintenanceMailer.notify_store(@maintenance).deliver_later unless @maintenance.part_in_stock
      redirect_to vehicle_path(@vehicle), notice: "Maintenance record was successfully created."
    else
      flash.now[:alert] = "Please correct the errors below."
      render :new, status: :unprocessable_entity
    end
  end

  # GET /vehicles/:vehicle_id/maintenances/:id/edit
  def edit; end

  # PATCH/PUT /vehicles/:vehicle_id/maintenances/:id
  def update
    if @maintenance.update(maintenance_params)
      redirect_to vehicle_path(@vehicle), notice: "Maintenance record was successfully updated."
    else
      flash.now[:alert] = "Please correct the errors below."
      render :edit, status: :unprocessable_entity
    end
  end

  # DELETE /vehicles/:vehicle_id/maintenances/:id
  def destroy
    @maintenance.destroy
    redirect_to vehicle_path(@vehicle), notice: "Maintenance record was successfully deleted."
  end

  private

  def set_vehicle
    @vehicle = Vehicle.find_by(id: params[:vehicle_id])
  end

  def set_maintenance
    @maintenance = @vehicle.maintenances.find(params[:id])
  end

  def maintenance_params
    params.require(:maintenance).permit(
      :date,
      :service_type,
      :cost,
      :notes,
      :mileage,
      :status,
      :assignment_type,
      :part_in_stock,
      :service_provider_id,
      :estimated_delivery_date,
      :source,
      :start_date,
      :end_date,
      :category
    )
  end
end
