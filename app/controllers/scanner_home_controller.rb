# app/controllers/home_controller.rb
class ScannerHomeController < ApplicationController
  before_action :authenticate_user!
  before_action :require_scanner_role!

  def index
  end

  private

  def require_scanner_role!
    return if current_user&.scanner_role?
    redirect_to root_path, alert: "Not authorized."
  end
end
