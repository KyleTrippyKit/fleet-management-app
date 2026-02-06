module Vmcott
  class ServiceProvidersController < ApplicationController
    before_action :authenticate_user!
    before_action :require_vmcott!
    before_action :set_service_provider, only: %i[show edit update destroy]

    def index
      @q = params[:q].to_s.strip
      scope = ServiceProvider.all.order(:name)
      scope = scope.where("name ILIKE ?", "%#{@q}%") if @q.present?

      @service_providers = scope
      @internal_workshops = scope.where(provider_type: "internal_workshop")
      @external_contractors = scope.where(provider_type: "external_contractor")
    end

    def show
    end

    def new
      @service_provider = ServiceProvider.new(provider_type: "external_contractor", is_active: true)
    end

    def create
      @service_provider = ServiceProvider.new(service_provider_params)
      if @service_provider.save
        redirect_to vmcott_service_providers_path, notice: "Service provider created."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
    end

    def update
      if @service_provider.update(service_provider_params)
        redirect_to vmcott_service_providers_path, notice: "Service provider updated."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @service_provider.destroy
      redirect_to vmcott_service_providers_path, notice: "Service provider deleted."
    end

    private

    def require_vmcott!
      # Your app stores agency code on current_user.agency.code
      unless current_user&.agency&.code == "VMCOTT" || admin?
        redirect_to root_path, alert: "Access denied. VMCOTT only."
      end
    end

    def set_service_provider
      @service_provider = ServiceProvider.find(params[:id])
    end

    def service_provider_params
      params.require(:service_provider).permit(
        :name,
        :provider_type,
        :contact_name,
        :phone,
        :email,
        :address,
        :is_active,
        :notes
      )
    end
  end
end
