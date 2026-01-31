# app/services/mock_payment_service.rb
class MockPaymentService
  # Trinidad bank BIN ranges (simplified mock data)
  BANK_BINS = {
    'first_citizens' => {
      name: 'First Citizens Bank',
      bins: ['4563', '5123', '4111'],
      success_rate: 0.95,
      processing_time: 1..3
    },
    'republic_bank' => {
      name: 'Republic Bank',
      bins: ['4567', '5127', '4117'],
      success_rate: 0.94,
      processing_time: 2..5
    },
    'scotiabank_tt' => {
      name: 'Scotiabank Trinidad',
      bins: ['4532', '5129', '4119'],
      success_rate: 0.93,
      processing_time: 1..4
    },
    'jmmb' => {
      name: 'JMMB Bank',
      bins: ['4556', '5126', '4116'],
      success_rate: 0.92,
      processing_time: 2..6
    }
  }.freeze

  class PaymentResult
    attr_reader :success, :transaction_id, :error_message, :bank_response, :retryable

    def initialize(success:, transaction_id: nil, error_message: nil, bank_response: {}, retryable: false)
      @success = success
      @transaction_id = transaction_id
      @error_message = error_message
      @bank_response = bank_response
      @retryable = retryable
    end

    def success?
      @success
    end

    def retryable?
      @retryable
    end
    
    # Optional convenience method
    def failure?
      !success?
    end
  end

  def self.process_payment(purchase_order:, user:, card_details:, billing_address:)
    new.process(purchase_order, user, card_details, billing_address)
  end

  def process(purchase_order, user, card_details, billing_address)
    # normalize keys to symbols (in case hashes come in as strings)
    card_details = (card_details || {}).transform_keys { |k| k.to_s.to_sym }
    billing_address = (billing_address || {}).transform_keys { |k| k.to_s.to_sym }

    # Validate card (mock rules)
    validation = validate_card(card_details)
    return validation unless validation.success?

    # Determine bank
    bank = identify_bank(card_details[:number])

    # Process payment with simulated bank response
    bank_response = simulate_bank_transaction(purchase_order, bank, card_details)

    # Create payment audit using PaymentAudit.log method
    PaymentAudit.log(
      purchase_order,
      user,
      'initiated',
      {
        amount: purchase_order.amount,
        bank: bank[:name],
        card_last_four: card_details[:number].to_s.gsub(/\s+/, '').last(4),
        mock_transaction: true,
        billing_address: billing_address,
        card_type: card_details[:card_type] || 'credit',
        timestamp: Time.current.iso8601,
        bank_bin: card_details[:number].to_s.gsub(/\s+/, '')[0..3]
      }
    )

    if bank_response[:success]
      # Success path
      transaction_id = generate_transaction_id(bank)

      PaymentAudit.log(
        purchase_order,
        user,
        'authorized',
        {
          transaction_id: transaction_id,
          authorization_code: bank_response[:authorization_code],
          bank_reference: bank_response[:bank_reference],
          bank_name: bank[:name],
          timestamp: Time.current.iso8601,
          response_code: bank_response[:response_code],
          approval_code: bank_response[:approval_code]
        }
      )

      simulate_processing_delay(bank[:processing_time])

      PaymentAudit.log(
        purchase_order,
        user,
        'completed',
        {
          settlement_time: Time.current.iso8601,
          final_amount: purchase_order.amount,
          transaction_id: transaction_id,
          completion_time: Time.current.iso8601,
          bank_settlement_reference: "SETTLE-#{SecureRandom.hex(6).upcase}",
          merchant_id: bank_response[:merchant_id],
          terminal_id: bank_response[:terminal_id]
        }
      )

      PaymentResult.new(
        success: true,
        transaction_id: transaction_id,
        bank_response: bank_response.merge(mock_system: true, transaction_id: transaction_id)
      )
    else
      # Failure path
      PaymentAudit.log(
        purchase_order,
        user,
        'failed',
        {
          error_code: bank_response[:error_code],
          error_message: bank_response[:message],
          retryable: bank_response[:retryable],
          bank_name: bank[:name],
          timestamp: Time.current.iso8601,
          failure_reason: bank_response[:message],
          response_code: bank_response[:response_code],
          card_last_four: card_details[:number].to_s.gsub(/\s+/, '').last(4)
        }
      )

      PaymentResult.new(
        success: false,
        error_message: "Bank declined: #{bank_response[:message]}",
        bank_response: bank_response,
        retryable: bank_response[:retryable]
      )
    end
  rescue => e
    Rails.logger.error "[MockPaymentService] Error: #{e.class}: #{e.message}"
    Rails.logger.error e.backtrace.join("\n") if Rails.env.development?

    # Log the error as a failed payment audit
    begin
      metadata = {
        error_class: e.class.to_s,
        error_message: e.message,
        retryable: true,
        system_error: true,
        timestamp: Time.current.iso8601
      }
      metadata[:stack_trace] = e.backtrace.first(5) if Rails.env.development?

      PaymentAudit.log(
        purchase_order,
        user,
        'failed',
        metadata
      )
    rescue => audit_error
      Rails.logger.error "[MockPaymentService] Failed to create audit: #{audit_error.message}"
    end

    PaymentResult.new(
      success: false,
      error_message: "Payment processing error: #{e.message}",
      retryable: true
    )
  end

  private

  def validate_card(card_details)
    errors = []

    errors << "Card number required" if card_details[:number].blank?
    errors << "Expiry month required" if card_details[:expiry_month].blank?
    errors << "Expiry year required" if card_details[:expiry_year].blank?
    errors << "CVV required" if card_details[:cvv].blank?

    if card_details[:number].present?
      card_number = card_details[:number].to_s.gsub(/\s+/, '')
      unless card_number.match?(/^\d{16}$/)
        errors << "Invalid card number (must be 16 digits)"
      end
      
      # Optional: Validate card is not expired
      if card_details[:expiry_month].present? && card_details[:expiry_year].present?
        expiry_month = card_details[:expiry_month].to_i
        expiry_year = card_details[:expiry_year].to_i
        
        # Convert two-digit year to four-digit
        current_year = Time.current.year
        if expiry_year < 100
          expiry_year += 2000
        end
        
        if expiry_year < current_year || (expiry_year == current_year && expiry_month < Time.current.month)
          errors << "Card has expired"
        end
      end
    end

    if errors.any?
      PaymentResult.new(success: false, error_message: errors.join(', '))
    else
      PaymentResult.new(success: true)
    end
  end

  def identify_bank(card_number)
    return BANK_BINS['first_citizens'] if card_number.blank?
    
    card_prefix = card_number.to_s.gsub(/\s+/, '')[0..3]

    BANK_BINS.each_value do |bank_info|
      return bank_info if bank_info[:bins].any? { |bin| card_prefix.start_with?(bin) }
    end

    BANK_BINS['first_citizens']  # Default bank
  end

  def simulate_bank_transaction(_purchase_order, bank, card_details)
    # Determine success based on bank's success rate
    success = rand <= bank[:success_rate]
    
    # Add some variability: if card has "0000" as last 4, always fail (test card)
    card_last_four = card_details[:number].to_s.gsub(/\s+/, '').last(4)
    if card_last_four == "0000"
      success = false
    end

    if success
      {
        success: true,
        authorization_code: SecureRandom.alphanumeric(6).upcase,
        bank_reference: "BANK-#{SecureRandom.hex(4).upcase}",
        transaction_time: Time.current.iso8601,
        bank_name: bank[:name],
        message: "Transaction approved",
        approval_code: "APP#{SecureRandom.hex(3).upcase}",
        response_code: "00",  # ISO 8583 success code
        merchant_id: "MOCK#{SecureRandom.hex(3).upcase}",
        terminal_id: "TERM#{SecureRandom.hex(2).upcase}"
      }
    else
      error_types = [
        { code: 'INSUFFICIENT_FUNDS', message: 'Insufficient funds', retryable: false },
        { code: 'INVALID_CARD', message: 'Invalid card details', retryable: false },
        { code: 'EXPIRED_CARD', message: 'Card has expired', retryable: false },
        { code: 'DECLINED', message: 'Transaction declined by bank', retryable: true },
        { code: 'TIMEOUT', message: 'Bank connection timeout', retryable: true },
        { code: 'DAILY_LIMIT', message: 'Daily transaction limit exceeded', retryable: false },
        { code: 'SECURITY_VIOLATION', message: 'Security violation detected', retryable: false },
        { code: 'CARD_BLOCKED', message: 'Card is blocked', retryable: false }
      ]

      error = error_types.sample
      
      # Special test card responses
      if card_last_four == "0000"
        error = { code: 'TEST_CARD', message: 'Test card - always fails', retryable: false }
      end

      {
        success: false,
        error_code: error[:code],
        message: error[:message],
        retryable: error[:retryable],
        bank_name: bank[:name],
        response_code: "51",  # ISO 8583 decline code
        merchant_id: "MOCK#{SecureRandom.hex(3).upcase}",
        terminal_id: "TERM#{SecureRandom.hex(2).upcase}"
      }
    end
  end

  def generate_transaction_id(bank)
    bank_code = bank[:name].split.first[0..2].upcase
    timestamp = Time.current.strftime('%Y%m%d%H%M%S')
    random = SecureRandom.hex(4).upcase
    "MOCK-#{bank_code}-#{timestamp}-#{random}"
  end

  def simulate_processing_delay(range)
    return unless (Rails.env.development? || Rails.env.test?)
    
    if range.is_a?(Range)
      sleep_time = rand(range)
      Rails.logger.info "[MockPaymentService] Simulating bank processing delay: #{sleep_time} seconds"
      sleep(sleep_time)
    end
  end
  
  # Test helper methods
  def self.generate_test_card(bank_code = 'first_citizens')
    bank = BANK_BINS[bank_code] || BANK_BINS['first_citizens']
    bin = bank[:bins].sample
    
    {
      number: "#{bin}#{SecureRandom.hex(6).to_i.to_s.ljust(12, '0')}".gsub(/\s+/, '')[0...16],
      expiry_month: sprintf('%02d', rand(1..12)),
      expiry_year: (Time.current.year + rand(1..5)).to_s,
      cvv: sprintf('%03d', rand(0..999)),
      card_type: ['debit', 'credit'].sample,
      card_holder: "TEST USER #{SecureRandom.hex(3).upcase}",
      test_card: true
    }
  end
  
  def self.generate_always_fail_card
    {
      number: "4563000000000000",  # Last 4 are "0000"
      expiry_month: sprintf('%02d', Time.current.month),
      expiry_year: (Time.current.year + 1).to_s,
      cvv: '123',
      card_type: 'credit',
      card_holder: "TEST FAIL CARD",
      test_card: true
    }
  end
  
  def self.generate_always_success_card
    {
      number: "4563111111111111",
      expiry_month: sprintf('%02d', Time.current.month),
      expiry_year: (Time.current.year + 1).to_s,
      cvv: '123',
      card_type: 'credit',
      card_holder: "TEST SUCCESS CARD",
      test_card: true
    }
  end
end