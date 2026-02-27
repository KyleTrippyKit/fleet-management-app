# app/controllers/agencies_controller.rb
class AgenciesController < ApplicationController
  before_action :authenticate_user!
  before_action :authorize_ptsc_admin!, only: [:index, :show]

  def index
    @agencies = Agency.all.order(:code)
  end

  def show
    @agency = Agency.find(params[:id])
    @users = @agency.users.order(:name).page(params[:page]).per(20)
    @vehicles = @agency.vehicles.order(:license_plate).limit(10)
  end

  private

  def authorize_ptsc_admin!
    unless current_user.admin? && current_user.agency&.code == 'PTSC'
      redirect_to root_path, alert: "You are not authorized to access this area."
    end
  end
end