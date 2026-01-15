# app/services/quickbooks_service.rb
class QuickbooksService
  class << self
    def authorization_url(user)
      oauth_client = OAuth2::Client.new(
        ENV['QUICKBOOKS_CLIENT_ID'],
        ENV['QUICKBOOKS_CLIENT_SECRET'],
        site: 'https://appcenter.intuit.com',
        authorize_url: 'https://appcenter.intuit.com/connect/oauth2',
        token_url: 'https://oauth.platform.intuit.com/oauth2/v1/tokens/bearer'
      )
      
      oauth_client.auth_code.authorize_url(
        redirect_uri: ENV['QUICKBOOKS_REDIRECT_URI'],
        response_type: 'code',
        state: user.id,
        scope: 'com.intuit.quickbooks.accounting'
      )
    end
    
    def handle_callback(user, code, realm_id)
      # Exchange code for tokens
      oauth_client = OAuth2::Client.new(
        ENV['QUICKBOOKS_CLIENT_ID'],
        ENV['QUICKBOOKS_CLIENT_SECRET'],
        site: 'https://appcenter.intuit.com',
        token_url: 'https://oauth.platform.intuit.com/oauth2/v1/tokens/bearer'
      )
      
      token = oauth_client.auth_code.get_token(
        code,
        redirect_uri: ENV['QUICKBOOKS_REDIRECT_URI']
      )
      
      # Create or update QuickbooksIntegration
      integration = QuickbooksIntegration.find_or_initialize_by(user_id: user.id)
      integration.update!(
        access_token: token.token,
        refresh_token: token.refresh_token,
        company_id: realm_id,
        realm_id: realm_id,
        token_expires_at: token.expires_at,
        connected: true
      )
    end
  end
end