class AuthTestController < ApplicationController
  skip_before_action :authenticate_user!
  skip_before_action :verify_authenticity_token
  
  def test
    if params[:email] && params[:password]
      user = User.find_by(email: params[:email])
      if user
        valid = user.valid_password?(params[:password])
        Rails.logger.info "Auth test: #{params[:email]} - Password valid? #{valid}"
        
        if valid
          sign_in(user)
          render plain: "Logged in as #{user.email}"
        else
          render plain: "Invalid password for #{params[:email]}"
        end
      else
        render plain: "User #{params[:email]} not found"
      end
    else
      render plain: "Send email and password parameters"
    end
  end
  
  def check
    render plain: "Current user: #{current_user&.email || 'NONE'}"
  end
end
