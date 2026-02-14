module Inspector
  class HomeController < ApplicationController
    before_action :authenticate_user!
    before_action :require_inspector_role!

    def index; end

    private

    def require_inspector_role!
      return if current_user&.inspector_role? || current_user&.admin?

      redirect_to root_path, alert: "Inspector access only."
    end
  end
end
