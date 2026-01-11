# app/controllers/users/sessions_controller.rb
class Users::SessionsController < Devise::SessionsController
  # Override the create action to add debugging
  def create
    self.resource = warden.authenticate!(auth_options)
    set_flash_message!(:notice, :signed_in)
    sign_in(resource_name, resource)
    
    # Debug logging
    Rails.logger.info "=== LOGIN SUCCESSFUL ==="
    Rails.logger.info "User: #{resource.email}"
    Rails.logger.info "Agency: #{resource.agency&.code}"
    Rails.logger.info "Redirecting to: #{after_sign_in_path_for(resource)}"
    Rails.logger.info "========================"
    
    yield resource if block_given?
    respond_with resource, location: after_sign_in_path_for(resource)
  end
end