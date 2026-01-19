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
  }

  class PaymentResult
    attr_reader :success, :transaction_id, :error_message, :bank_response, :retryable

    def initialize(success:, transaction_id: nil, error_message: nil, bank_response: {}, retryable: false)
      @success = success
      @transaction_id = transaction_id
      @error_message = error_message
      @bank_response = bank_response
      @retryable = retryable
    end
  end

  def self.process_payment(purchase_order:, user:, card_details:, billing_address:)
    new.process(purchase_order, user, card_details, billing_address)
  end

  def process(purchase_order, user, card_details, billing_address)
    begin
      # Validate card
      validation = validate_card(card_details)
      return validation unless validation.success

      # Determine bank
      bank = identify_bank(card_details[:number])
      
      # Process payment with simulated bank response
      bank_response = simulate_bank_transaction(purchase_order, bank, card_details)
      
      # Create payment audit
      create_payment_audit(purchase_order, user, 'initiated', {
        amount: purchase_order.amount,
        bank: bank[:name],
        card_last_four: card_details[:number].to_s.last(4),
        mock_transaction: true
      })

      if bank_response[:success]
        # Success path
        transaction_id = generate_transaction_id(bank)
        
        create_payment_audit(purchase_order, user, 'authorized', {
          transaction_id: transaction_id,
          authorization_code: bank_response[:authorization_code]
        })

        # Simulate processing delay
        simulate_processing_delay(bank[:processing_time])

        create_payment_audit(purchase_order, user, 'completed', {
          settlement_time: Time.current.iso8601,
          final_amount: purchase_order.amount
        })

        PaymentResult.new(
          success: true,
          transaction_id: transaction_id,
          bank_response: bank_response.merge(mock_system: true)
        )
      else
        # Failure path
        create_payment_audit(purchase_order, user, 'failed', {
          error_code: bank_response[:error_code],
          error_message: bank_response[:message],
          retryable: bank_response[:retryable]
        })

        PaymentResult.new(
          success: false,
          error_message: "Bank declined: #{bank_response[:message]}",
          bank_response: bank_response,
          retryable: bank_response[:retryable]
        )
      end

    rescue => e
      Rails.logger.error "[MockPaymentService] Error: #{e.message}"
      PaymentResult.new(
        success: false,
        error_message: "Payment processing error: #{e.message}",
        retryable: true
      )
    end
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
      errors << "Invalid card number" unless card_number.match?(/^\d{16}$/)
    end

    if errors.any?
      PaymentResult.new(success: false, error_message: errors.join(', '))
    else
      PaymentResult.new(success: true)
    end
  end

  def identify_bank(card_number)
    card_prefix = card_number.to_s.gsub(/\s+/, '')[0..3]
    
    BANK_BINS.each do |bank_code, bank_info|
      return bank_info if bank_info[:bins].any? { |bin| card_prefix.start_with?(bin) }
    end
    
    # Default to First Citizens
    BANK_BINS['first_citizens']
  end

  def simulate_bank_transaction(purchase_order, bank, card_details)
    # Determine if transaction should succeed based on success rate
    success = rand <= bank[:success_rate]
    
    if success
      {
        success: true,
        authorization_code: SecureRandom.alphanumeric(6).upcase,
        bank_reference: "BANK-#{SecureRandom.hex(4).upcase}",
        transaction_time: Time.current.iso8601,
        bank_name: bank[:name],
        message: "Transaction approved"
      }
    else
      error_types = [
        { code: 'INSUFFICIENT_FUNDS', message: 'Insufficient funds', retryable: false },
        { code: 'INVALID_CARD', message: 'Invalid card details', retryable: false },
        { code: 'EXPIRED_CARD', message: 'Card has expired', retryable: false },
        { code: 'DECLINED', message: 'Transaction declined', retryable: true },
        { code: 'TIMEOUT', message: 'Bank connection timeout', retryable: true }
      ]
      
      error = error_types.sample
      
      {
        success: false,
        error_code: error[:code],
        message: error[:message],
        retryable: error[:retryable],
        bank_name: bank[:name]
      }
    end
  end

  def generate_transaction_id(bank)
    bank_code = bank[:name].split.first[0..2].upcase
    "MOCK-#{bank_code}-#{Time.current.to_i}-#{SecureRandom.hex(4).upcase}"
  end

  def simulate_processing_delay(range)
    # Only simulate delay in development/test
    if Rails.env.development? || Rails.env.test?
      sleep rand(range) if range.is_a?(Range)
    end
  end

  def create_payment_audit(purchase_order, user, action, metadata = {})
    return unless purchase_order.respond_to?(:payment_audits)
    
    purchase_order.payment_audits.create!(
      user: user,
      action: action,
      metadata: metadata.merge(
        timestamp: Time.current.iso8601,
        environment: Rails.env,
        mock_system: true
      ),
      ip_address: Thread.current[:request]&.remote_ip || '127.0.0.1',
      user_agent: Thread.current[:request]&.user_agent || 'MockPaymentService'
    )
  rescue => e
    Rails.logger.error "[MockPaymentService] Failed to create audit: #{e.message}"
  end
end