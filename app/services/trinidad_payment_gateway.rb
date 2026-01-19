# app/services/trinidad_payment_gateway.rb
class TrinidadPaymentGateway
  # Mock bank API endpoints (replace with actual Trinidad bank APIs)
  BANKS = {
    'first_citizens' => {
      name: 'First Citizens Bank',
      api_url: ENV['FIRST_CITIZENS_API_URL'],
      test_url: ENV['FIRST_CITIZENS_TEST_URL']
    },
    'republic_bank' => {
      name: 'Republic Bank',
      api_url: ENV['REPUBLIC_BANK_API_URL'],
      test_url: ENV['REPUBLIC_BANK_TEST_URL']
    },
    'scotiabank' => {
      name: 'Scotiabank Trinidad',
      api_url: ENV['SCOTIABANK_TT_API_URL'],
      test_url: ENV['SCOTIABANK_TT_TEST_URL']
    },
    'jmmb' => {
      name: 'JMMB Bank',
      api_url: ENV['JMMB_API_URL'],
      test_url: ENV['JMMB_TEST_URL']
    }
  }

  PaymentResult = Struct.new(:success, :transaction_id, :error_message, :bank_response, :retryable, keyword_init: true)

  class << self
    def process(amount:, card_details:, billing_address:, reference:)
      begin
        # Validate card details for Trinidad banks
        validation_errors = validate_trinidad_card(card_details)
        return PaymentResult.new(success: false, error_message: validation_errors.join(', ')) if validation_errors.any?

        # Determine which Trinidad bank the card belongs to
        bank = identify_trinidad_bank(card_details[:number])
        
        # Process with appropriate bank (mock implementation)
        if Rails.env.production?
          # Real API call to Trinidad bank
          response = call_bank_api(bank, amount, card_details, billing_address, reference)
        else
          # Mock response for development
          response = mock_bank_response(bank, amount, card_details, reference)
        end

        handle_bank_response(response, bank)

      rescue Timeout::Error => e
        handle_error(e)
      rescue SocketError => e
        handle_error(e)
      rescue JSON::ParserError => e
        handle_error(e)
      rescue StandardError => e
        Rails.logger.error "[TrinidadPaymentGateway] Error: #{e.message}\n#{e.backtrace.join("\n")}"
        PaymentResult.new(
          success: false, 
          error_message: "Payment processing failed: #{e.message}",
          retryable: retryable?(e)
        )
      end
    end

    def handle_error(exception)
      case exception
      when Timeout::Error
        PaymentResult.new(
          success: false, 
          error_message: "Bank connection timeout. Please try again.",
          retryable: true
        )
      when SocketError
        PaymentResult.new(
          success: false, 
          error_message: "Network error connecting to bank. Check your internet connection.",
          retryable: true
        )
      when JSON::ParserError
        PaymentResult.new(
          success: false, 
          error_message: "Invalid response from bank. Please contact support.",
          retryable: false
        )
      else
        PaymentResult.new(
          success: false, 
          error_message: "Payment processing failed",
          retryable: false
        )
      end
    end

    def retryable?(error)
      [Timeout::Error, SocketError].any? { |e| error.is_a?(e) }
    end

    def mask_card_number(card_number)
      return "" if card_number.blank?
      card_number = card_number.gsub(/\s+/, '')
      "**** **** **** #{card_number.last(4)}"
    end

    def encrypt_card_data(card_data)
      # Use Rails encryption for sensitive data
      encryptor = ActiveSupport::MessageEncryptor.new(
        Rails.application.credentials.secret_key_base[0..31]
      )
      encryptor.encrypt_and_sign(card_data.to_json)
    end

    def decrypt_card_data(encrypted_data)
      encryptor = ActiveSupport::MessageEncryptor.new(
        Rails.application.credentials.secret_key_base[0..31]
      )
      JSON.parse(encryptor.decrypt_and_verify(encrypted_data))
    rescue
      {}
    end

    private

    def validate_trinidad_card(card_details)
      errors = []
      
      # Basic validation
      errors << "Card number is required" if card_details[:number].blank?
      errors << "Expiry month is required" if card_details[:expiry_month].blank?
      errors << "Expiry year is required" if card_details[:expiry_year].blank?
      errors << "CVV is required" if card_details[:cvv].blank?
      
      # Validate Trinidad card number patterns
      if card_details[:number].present?
        errors << "Invalid card number format" unless valid_trinidad_card_format?(card_details[:number])
      end
      
      # Validate expiry date
      if card_details[:expiry_month].present? && card_details[:expiry_year].present?
        expiry_date = Date.new(card_details[:expiry_year].to_i, card_details[:expiry_month].to_i, 1).end_of_month
        errors << "Card has expired" if expiry_date < Date.current
      end
      
      errors
    end

    def valid_trinidad_card_format?(card_number)
      card_number = card_number.gsub(/\s+/, '')
      
      # Common Trinidad bank BIN ranges (simplified)
      trinidad_bin_ranges = [
        '4'[0],           # Visa (typically)
        '5'[0],           # MasterCard
        '3'[0..1],        # American Express (may start with 34, 37)
      ]
      
      trinidad_bin_ranges.any? { |bin| card_number.start_with?(bin) }
    end

    def identify_trinidad_bank(card_number)
      # Simplified bank identification by BIN
      card_number = card_number.gsub(/\s+/, '')
      
      case card_number[0]
      when '4'
        BANKS['first_citizens'] # Visa cards often issued by FCB
      when '5'
        BANKS['republic_bank']  # MasterCard often issued by Republic
      when '3'
        BANKS['scotiabank']     # Amex often by Scotiabank
      else
        BANKS['first_citizens'] # Default
      end
    end

    def call_bank_api(bank, amount, card_details, billing_address, reference)
      # This is where you'd integrate with actual Trinidad bank APIs
      # Using Faraday or similar HTTP client
      
      # Mock implementation - replace with actual API calls
      {
        success: true,
        transaction_id: "TT-#{reference}-#{SecureRandom.hex(8)}",
        bank_reference: SecureRandom.alphanumeric(12).upcase,
        authorization_code: SecureRandom.alphanumeric(6).upcase,
        timestamp: Time.current.iso8601,
        bank_name: bank[:name]
      }
    end

    def mock_bank_response(bank, amount, card_details, reference)
      # Simulate various bank responses for testing
      success_rate = Rails.env.test? ? 1.0 : 0.95 # 95% success rate in dev
      
      if rand < success_rate
        {
          success: true,
          transaction_id: "TT-#{reference}-#{SecureRandom.hex(8)}",
          bank_reference: "BANK-REF-#{SecureRandom.alphanumeric(8)}",
          authorization_code: SecureRandom.alphanumeric(6).upcase,
          timestamp: Time.current.iso8601,
          bank_name: bank[:name],
          message: "Transaction approved"
        }
      else
        {
          success: false,
          error_code: %w[INSUFFICIENT_FUNDS INVALID_CARD EXPIRED_CARD DECLINED].sample,
          message: "Transaction declined by bank",
          bank_name: bank[:name]
        }
      end
    end

    def handle_bank_response(response, bank)
      if response[:success]
        PaymentResult.new(
          success: true,
          transaction_id: response[:transaction_id],
          bank_response: response
        )
      else
        PaymentResult.new(
          success: false,
          error_message: "Bank declined: #{response[:message]}",
          bank_response: response
        )
      end
    end
  end
end