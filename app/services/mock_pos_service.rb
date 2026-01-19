# app/services/mock_pos_service.rb
class MockPosService
  TAX_RATE = 0.125  # Trinidad VAT/GCT 12.5%
  
  class ReceiptData
    attr_accessor :transaction_id, :items, :subtotal, :tax, :total, :payment_method, :change_due
    
    def initialize
      @items = []
      @subtotal = 0.0
      @tax = 0.0
      @total = 0.0
      @change_due = 0.0
    end
  end
  
  def self.process_sale(items:, payment_method:, amount_tendered: 0)
    new.process_sale(items, payment_method, amount_tendered)
  end
  
  def process_sale(items, payment_method, amount_tendered)
    receipt = ReceiptData.new
    
    # Generate mock transaction ID
    receipt.transaction_id = "POS-#{Time.current.strftime('%Y%m%d')}-#{SecureRandom.hex(4).upcase}"
    
    # Calculate totals
    items.each do |item|
      line_total = item[:quantity] * item[:price]
      receipt.items << item.merge(total: line_total)
      receipt.subtotal += line_total
    end
    
    # Calculate tax
    receipt.tax = receipt.subtotal * TAX_RATE
    receipt.total = receipt.subtotal + receipt.tax
    
    # Calculate change for cash payments
    if payment_method == 'cash' && amount_tendered > 0
      receipt.change_due = amount_tendered - receipt.total
    end
    
    receipt.payment_method = payment_method
    
    # Simulate receipt printing delay
    simulate_printing_delay
    
    {
      success: true,
      receipt: receipt,
      transaction_id: receipt.transaction_id,
      timestamp: Time.current
    }
  rescue => e
    {
      success: false,
      error: "Transaction failed: #{e.message}",
      timestamp: Time.current
    }
  end
  
  def self.generate_receipt_html(receipt_data)
    <<~HTML
      <!DOCTYPE html>
      <html>
      <head>
        <title>Receipt #{receipt_data.transaction_id}</title>
        <style>
          body { font-family: 'Courier New', monospace; font-size: 12px; }
          .receipt { width: 300px; margin: 0 auto; padding: 10px; }
          .header { text-align: center; border-bottom: 1px dashed #000; padding-bottom: 10px; margin-bottom: 10px; }
          .item-row { display: flex; justify-content: space-between; margin: 2px 0; }
          .total-row { border-top: 2px solid #000; margin-top: 10px; padding-top: 10px; font-weight: bold; }
          .footer { text-align: center; margin-top: 20px; font-size: 10px; color: #666; }
        </style>
      </head>
      <body>
        <div class="receipt">
          <div class="header">
            <h3>TRINIDAD FLEET MANAGEMENT</h3>
            <p>DEMO SYSTEM - MOCK RECEIPT</p>
            <p>Transaction: #{receipt_data.transaction_id}</p>
            <p>Date: #{Time.current.strftime('%Y-%m-%d %H:%M:%S')}</p>
          </div>
          
          <div class="items">
            #{receipt_data.items.map do |item|
              "<div class='item-row'>
                <span>#{item[:name]} x#{item[:quantity]}</span>
                <span>TTD #{(item[:total] || 0).round(2)}</span>
              </div>"
            end.join}
          </div>
          
          <div class="totals">
            <div class="item-row">
              <span>Subtotal:</span>
              <span>TTD #{receipt_data.subtotal.round(2)}</span>
            </div>
            <div class="item-row">
              <span>Tax (12.5%):</span>
              <span>TTD #{receipt_data.tax.round(2)}</span>
            </div>
            <div class="item-row total-row">
              <span>Total:</span>
              <span>TTD #{receipt_data.total.round(2)}</span>
            </div>
            
            #{if receipt_data.payment_method == 'cash' && receipt_data.change_due > 0
              "<div class='item-row'>
                <span>Amount Tendered:</span>
                <span>TTD #{receipt_data.total.round(2)}</span>
              </div>
              <div class='item-row'>
                <span>Change Due:</span>
                <span>TTD #{receipt_data.change_due.round(2)}</span>
              </div>"
            end}
          </div>
          
          <div class="footer">
            <p>Payment Method: #{receipt_data.payment_method.upcase}</p>
            <p>*** DEMO TRANSACTION ***</p>
            <p>No actual funds were processed</p>
            <p>Thank you for your business!</p>
          </div>
        </div>
      </body>
      </html>
    HTML
  end
  
  private
  
  def simulate_printing_delay
    # Simulate thermal printer delay
    sleep rand(0.5..2.0) if Rails.env.development?
  end
end