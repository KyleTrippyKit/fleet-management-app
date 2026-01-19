# app/services/mock_trinidad_bank_service.rb
class MockTrinidadBankService
  def self.process_payment(amount:, card_details:, vendor:)
    {
      success: rand > 0.1, # 90% success rate for mock
      transaction_id: "TT-#{Time.now.to_i}-#{rand(1000..9999)}",
      bank_reference: "BANK#{SecureRandom.hex(4).upcase}",
      authorization_code: SecureRandom.hex(3).upcase,
      timestamp: Time.current,
      bank_name: card_details[:card_brand] == 'visa' ? 'First Citizens Bank' : 'Republic Bank'
    }
  end
end