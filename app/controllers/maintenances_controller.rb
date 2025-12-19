class MaintenancesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_vehicle
  before_action :set_maintenance, only: [:show, :edit, :update, :destroy, :mark_completed, :confirm_delete]

  # GET /vehicles/:vehicle_id/maintenances
  def index
    @maintenances = if @vehicle.present?
                      @vehicle.maintenances.order(
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
                      Maintenance.includes(:vehicle).order(
                        Arel.sql("
                          CASE status 
                            WHEN 'Pending' THEN 0 
                            WHEN 'Completed' THEN 1 
                            ELSE 2 
                          END ASC,
                          date ASC
                        ")
                      )
                    end
  end

  # GET /vehicles/:vehicle_id/maintenances/:id/confirm_delete
  def confirm_delete
    # Renders a confirmation page before deletion
  end

  # DELETE /vehicles/:vehicle_id/maintenances/:id
  def destroy
    @maintenance.destroy
    redirect_to vehicle_path(@vehicle), notice: "Maintenance record was successfully deleted."
  end

  # PATCH /vehicles/:vehicle_id/maintenances/:id/mark_completed
  def mark_completed
    if @maintenance.update(status: "Completed")
      redirect_to maintenance_dashboard_vehicles_path, notice: "Maintenance marked as completed."
    else
      redirect_to maintenance_dashboard_vehicles_path, alert: "Could not mark maintenance as completed."
    end
  end

  # GET /vehicles/:vehicle_id/maintenances/:id
  def show; end

  # GET /vehicles/:vehicle_id/maintenances/new
  def new
    @maintenance = @vehicle.maintenances.new
    @maintenance.mileage ||= @vehicle.mileage
    @service_providers = ServiceProvider.all
  end

  # POST /vehicles/:vehicle_id/maintenances
  def create
    @maintenance = @vehicle.maintenances.new(maintenance_params)
    @service_providers = ServiceProvider.all
    if @maintenance.save
      MaintenanceMailer.notify_store(@maintenance).deliver_later unless @maintenance.part_in_stock
      redirect_to vehicle_path(@vehicle), notice: "Maintenance record was successfully created."
    else
      flash.now[:alert] = "Please correct the errors below."
      render :new, status: :unprocessable_entity
    end
  end

  # GET /vehicles/:vehicle_id/maintenances/:id/edit
  def edit
    @service_providers = ServiceProvider.all
  end

  # PATCH/PUT /vehicles/:vehicle_id/maintenances/:id
  def update
    @service_providers = ServiceProvider.all
    if @maintenance.update(maintenance_params)
      redirect_to vehicle_path(@vehicle), notice: "Maintenance record was successfully updated."
    else
      flash.now[:alert] = "Please correct the errors below."
      render :edit, status: :unprocessable_entity
    end
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
      :date, :next_due_date, :reminder_sent_at, :service_type, :cost,
      :notes, :mileage, :status, :assignment_type, :part_in_stock,
      :service_provider_id, :estimated_delivery_date, :source, :start_date,
      :end_date, :category, :urgency
    )
  end
end
