# Trinidad Payment System Configuration
Rails.application.configure do
  config.trinidad_payments = ActiveSupport::OrderedOptions.new
  
  # Bank API endpoints (configure in credentials or environment variables)
  config.trinidad_payments.first_citizens_api_url = ENV['FIRST_CITIZENS_API_URL']
  config.trinidad_payments.republic_bank_api_url = ENV['REPUBLIC_BANK_API_URL']
  config.trinidad_payments.scotiabank_tt_api_url = ENV['SCOTIABANK_TT_API_URL']
  config.trinidad_payments.jmmb_api_url = ENV['JMMB_API_URL']
  
  # Transaction limits (Central Bank of Trinidad guidelines)
  config.trinidad_payments.max_single_transaction = 50_000.00
  config.trinidad_payments.daily_agency_limit = 150_000.00
  config.trinidad_payments.monthly_agency_limit = 1_000_000.00
  
  # Processing settings
  config.trinidad_payments.auto_reconciliation = true
  config.trinidad_payments.reconciliation_frequency = :daily # :daily, :weekly, :monthly
  config.trinidad_payments.compliance_auto_check = true
  
  # Retry settings
  config.trinidad_payments.max_retries = 3
  config.trinidad_payments.retry_delay = [30.seconds, 5.minutes, 15.minutes]
  
  # Monitoring
  config.trinidad_payments.monitoring_enabled = true
  config.trinidad_payments.alert_thresholds = {
    failure_rate: 5.0, # percentage
    avg_processing_time: 300, # seconds
    daily_volume: 100 # transactions
  }
end