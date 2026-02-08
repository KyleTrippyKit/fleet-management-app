# frozen_string_literal: true

module Vmcott
  class ServiceProvidersController < ApplicationController
    before_action :authenticate_user!

    before_action :set_vmcott_agency
    before_action :set_service_provider, only: %i[show edit update destroy]

    # GET /vmcott/service_providers
    def index
      @service_providers = ServiceProvider
        .where(agency_id: @vmcott_agency.id)
        .order(is_active: :desc, name: :asc)

      # Search
      if params[:q].present?
        q = "%#{params[:q].strip}%"
        @service_providers = @service_providers.where(
          "name ILIKE :q OR contact_name ILIKE :q OR phone ILIKE :q OR email ILIKE :q OR address ILIKE :q",
          q: q
        )
      end

      # Type filter: internal_workshop / external_contractor
      if params[:type].present?
        @service_providers = @service_providers.where(provider_type: params[:type])
      end

      # Active filter: 1 / 0
      if params[:active].present?
        @service_providers = @service_providers.where(is_active: params[:active] == "1")
      end
    end

    # GET /vmcott/service_providers/:id
    def show
    end

    # GET /vmcott/service_providers/new
    def new
      @service_provider = ServiceProvider.new(
        agency_id: @vmcott_agency.id,
        provider_type: "internal_workshop",
        is_active: true
      )
    end

    # POST /vmcott/service_providers
    def create
      @service_provider = ServiceProvider.new(service_provider_params)
      @service_provider.agency_id = @vmcott_agency.id

      if @service_provider.save
        redirect_to vmcott_service_provider_path(@service_provider), notice: "Service provider created."
      else
        flash.now[:alert] = @service_provider.errors.full_messages.to_sentence
        render :new, status: :unprocessable_entity
      end
    end

    # GET /vmcott/service_providers/:id/edit
    def edit
    end

    # PATCH/PUT /vmcott/service_providers/:id
    def update
      attrs = service_provider_params.to_h
      attrs["agency_id"] = @vmcott_agency.id

      if @service_provider.update(attrs)
        redirect_to vmcott_service_provider_path(@service_provider), notice: "Service provider updated."
      else
        flash.now[:alert] = @service_provider.errors.full_messages.to_sentence
        render :edit, status: :unprocessable_entity
      end
    end

    # DELETE /vmcott/service_providers/:id
    def destroy
      @service_provider.destroy
      redirect_to vmcott_service_providers_path, notice: "Service provider deleted."
    end

    private

    def set_vmcott_agency
      @vmcott_agency = Agency.find_by!(code: "vmcott")
    end

    def set_service_provider
      # Lock to VMCOTT only (but allow both provider types)
      @service_provider = ServiceProvider.find_by!(
        id: params[:id],
        agency_id: @vmcott_agency.id
      )
    end

    def service_provider_params
      params.require(:service_provider).permit(
        :name,
        :provider_type, # allow selecting internal/external
        :address,
        :contact_name,
        :phone,
        :email,
        :is_active,
        :notes
      )
    end
  end
end
