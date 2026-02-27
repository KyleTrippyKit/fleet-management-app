# app/controllers/admin/users_controller.rb
class Admin::UsersController < ApplicationController
  before_action :authenticate_user!
  before_action :authorize_ptsc_admin!
  before_action :set_user, only: [:edit, :update, :destroy, :impersonate, :reset_password]

  def index
    @users = User.includes(:agency).where(agency: current_user.agency) # Only PTSC users
    @users = apply_filters(@users)
    @users = @users.order(created_at: :desc).page(params[:page]).per(20)
    @agencies = [current_user.agency] # Only current agency (PTSC)
  end

  def new
    @user = User.new
    @user.agency = current_user.agency # Auto-assign to PTSC
    @agencies = [current_user.agency]
  end

  def create
    @user = User.new(user_params)
    @user.agency = current_user.agency # Force PTSC agency
    @user.password = SecureRandom.hex(8) # Generate random password
    
    if @user.save
      # You could send an email here with the password
      redirect_to admin_users_path, notice: "User created successfully. Password: #{@user.password}"
    else
      @agencies = [current_user.agency]
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @agencies = [current_user.agency]
  end

  def update
    if @user.update(user_params.except(:password, :agency_id)) # Don't allow agency change
      redirect_to admin_users_path, notice: "User updated successfully."
    else
      @agencies = [current_user.agency]
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    if @user == current_user
      redirect_to admin_users_path, alert: "You cannot delete yourself."
    elsif @user.agency != current_user.agency
      redirect_to admin_users_path, alert: "You can only delete users from your agency."
    else
      @user.destroy
      redirect_to admin_users_path, notice: "User deleted successfully."
    end
  end

  def impersonate
    if @user == current_user
      redirect_to admin_users_path, alert: "You cannot impersonate yourself."
    elsif @user.agency != current_user.agency
      redirect_to admin_users_path, alert: "You can only impersonate users from your agency."
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
    @user = User.find(params[:user_id])
    
    if @user.agency != current_user.agency
      redirect_to admin_users_path, alert: "You can only reset passwords for users in your agency."
      return
    end
    
    new_password = SecureRandom.hex(8)
    @user.update(password: new_password, reset_password_sent_at: Time.current)
    
    redirect_to admin_users_path, notice: "Password reset for #{@user.email}. New password: #{new_password}"
  end

  private

  def set_user
    @user = User.find(params[:id])
    # Ensure user belongs to PTSC
    if @user.agency != current_user.agency
      redirect_to admin_users_path, alert: "You can only access users from your agency."
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
      :email, :name, :role, :employee_id, :time_zone, :is_active
    ).merge(agency_id: current_user.agency_id) # Force agency_id to PTSC
  end

  def authorize_ptsc_admin!
    unless current_user.admin? && current_user.agency&.code == 'PTSC'
      redirect_to root_path, alert: "You are not authorized to access this area."
    end
  end
end