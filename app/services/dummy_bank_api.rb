# app/services/dummy_bank_api.rb
class DummyBankApi
  ENDPOINTS = {
    'first_citizens' => 'https://sandbox.firstcitizens.tt/api/v1/payments',
    'republic_bank' => 'https://sandbox.republicbank.tt/api/payments'
  }
  
  def self.mock_response
    {
      "status": "approved",
      "transactionId": "FCB#{SecureRandom.hex(8).upcase}",
      "amount": params[:amount],
      "timestamp": Time.now.utc.iso8601,
      "message": "Transaction processed successfully"
    }
  end
end