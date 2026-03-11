# app/controllers/admin/users_controller.rb
class Admin::UsersController < ApplicationController
  before_action :authenticate_user!
  before_action :authorize_admin!
  before_action :set_user, only: [:edit, :update, :destroy, :impersonate, :reset_password]
  before_action :ensure_same_agency!, only: [:edit, :update, :destroy, :impersonate, :reset_password]

  def index
    @users = User.includes(:agency).where(agency: current_user.agency)
    @users = apply_filters(@users)
    @users = @users.order(created_at: :desc).page(params[:page]).per(20)
    @agencies = [current_user.agency]
  end

  def new
    @user = User.new
    # Set agency from params or default to current user's agency
    if params[:agency_id].present?
      @user.agency = Agency.find(params[:agency_id])
    else
      @user.agency = current_user.agency
    end
    @agencies = [current_user.agency]
  end

  def create
    @user = User.new(user_params)
    
    # Set agency from params or default to current user's agency
    if params[:agency_id].present?
      @user.agency_id = params[:agency_id]
    else
      @user.agency_id = current_user.agency_id
    end
    
    # Generate random password
    @user.password = SecureRandom.hex(8)
    
    if @user.save
      redirect_to admin_users_path, notice: "User created successfully for #{@user.agency.code}. Password: #{@user.password}"
    else
      @agencies = [current_user.agency]
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @agencies = [current_user.agency]
  end

  def update
    if @user.update(user_params.except(:password, :agency_id))
      redirect_to admin_users_path, notice: "User updated successfully."
    else
      @agencies = [current_user.agency]
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    if @user == current_user
      redirect_to admin_users_path, alert: "You cannot delete yourself."
    else
      # First, nullify any associations that might exist
      # You may need to update other records here if they reference this user
      begin
        @user.destroy
        redirect_to admin_users_path, notice: "User deleted successfully."
      rescue => e
        redirect_to admin_users_path, alert: "Could not delete user: #{e.message}"
      end
    end
  end

  def impersonate
    if @user == current_user
      redirect_to admin_users_path, alert: "You cannot impersonate yourself."
    else
      session[:admin_id] = current_user.id
      sign_in(:user, @user, bypass: true)
      redirect_to root_path, notice: "Now impersonating #{@user.email}"
    end
  end

  def stop_impersonating
    if session[:admin_id].present?
      admin = User.find(session[:admin_id])
      session.delete(:admin_id)
      sign_in(:user, admin, bypass: true)
      redirect_to admin_users_path, notice: "Stopped impersonating."
    else
      redirect_to root_path
    end
  end

  def reset_password
    new_password = SecureRandom.hex(8)
    @user.update(password: new_password, reset_password_sent_at: Time.current)
    
    redirect_to admin_users_path, notice: "Password reset for #{@user.email}. New password: #{new_password}"
  end

  private

  def set_user
    @user = User.find(params[:id])
  end

  def ensure_same_agency!
    if @user.agency_id != current_user.agency_id
      redirect_to admin_users_path, alert: "You can only manage users from your own agency."
    end
  end

  def apply_filters(users)
    users = users.where("email ILIKE :search OR name ILIKE :search", search: "%#{params[:search]}%") if params[:search].present?
    users = users.where(role: params[:role]) if params[:role].present?
    users = users.where(is_active: params[:status] == 'active') if params[:status].present?
    users
  end

  def user_params
    params.require(:user).permit(
      :email, :name, :role, :employee_id, :time_zone, :is_active, :theme_preference
    )
  end

  def authorize_admin!
    unless current_user.admin?
      redirect_to root_path, alert: "You are not authorized to access this area."
    end
  end
end