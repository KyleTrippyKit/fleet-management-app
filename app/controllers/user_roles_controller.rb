# app/controllers/user_roles_controller.rb
class UserRolesController < ApplicationController
  before_action :authenticate_user!
  before_action :authorize_admin!
  
  def edit
    @user = User.find(params[:id])
    @roles = Role.all.order(:category, :name)
  end
  
  def update
    @user = User.find(params[:id])
    
    if @user.update(user_role_params)
      redirect_to users_path, notice: "User roles updated successfully."
    else
      @roles = Role.all.order(:category, :name)
      render :edit, status: :unprocessable_entity
    end
  end
  
  private
  
  def authorize_admin!
    unless current_user.admin?
      redirect_to root_path, alert: "Administrator access required."
    end
  end
  
  def user_role_params
    params.require(:user).permit(role_ids: [])
  end
end