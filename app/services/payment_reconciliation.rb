# app/services/payment_reconciliation.rb
class PaymentReconciliation
  class ReconciliationResult
    attr_reader :matched, :discrepancies, :unmatched_payments, :unmatched_bank_records

    def initialize(matched: [], discrepancies: [], unmatched_payments: [], unmatched_bank_records: [])
      @matched = matched
      @discrepancies = discrepancies
      @unmatched_payments = unmatched_payments
      @unmatched_bank_records = unmatched_bank_records
    end

    def success?
      discrepancies.empty? && unmatched_payments.empty? && unmatched_bank_records.empty?
    end
  end

  class << self
    def reconcile_trinidad_payments(start_date:, end_date:, agency_id: nil)
      # Get all Trinidad card payments in date range
      payments = PurchaseOrder
        .where(payment_method: ['trinidad_credit_card', 'trinidad_debit_card'])
        .where(payment_status: 'completed')
        .where(payment_date: start_date.beginning_of_day..end_date.end_of_day)
      
      payments = payments.for_agency(agency_id) if agency_id.present?
      
      # Get bank statement records (mock - integrate with actual bank API)
      bank_records = fetch_bank_statement_records(start_date, end_date, agency_id)
      
      # Perform reconciliation
      reconcile(payments, bank_records)
    end

    def find_discrepancies(agency_id: nil)
      # Find payments with potential issues
      payments = PurchaseOrder
        .where(payment_method: ['trinidad_credit_card', 'trinidad_debit_card'])
        .where(payment_status: 'completed')
      
      payments = payments.for_agency(agency_id) if agency_id.present?
      
      discrepancies = []
      
      payments.find_each do |payment|
        # Check for missing bank confirmation
        if payment.payment_reference.present? && !bank_confirmation_exists?(payment)
          discrepancies << {
            type: 'missing_bank_confirmation',
            purchase_order: payment,
            message: "No bank statement record found for payment reference #{payment.payment_reference}"
          }
        end
        
        # Check for amount mismatches
        if bank_amount_mismatch?(payment)
          discrepancies << {
            type: 'amount_mismatch',
            purchase_order: payment,
            message: "Payment amount #{payment.amount} doesn't match bank record"
          }
        end
        
        # Check for delayed settlement (payment completed but not settled by bank)
        if payment.paid_at && payment.paid_at < 3.days.ago && !bank_settlement_complete?(payment)
          discrepancies << {
            type: 'delayed_settlement',
            purchase_order: payment,
            message: "Payment made #{distance_of_time_in_words(payment.paid_at, Time.current)} ago but not settled by bank"
          }
        end
      end
      
      discrepancies
    end

    def generate_reconciliation_report(start_date:, end_date:, agency_id: nil)
      result = reconcile_trinidad_payments(
        start_date: start_date,
        end_date: end_date,
        agency_id: agency_id
      )
      
      {
        reconciliation_date: Time.current,
        period: { start_date: start_date, end_date: end_date },
        summary: {
          total_payments: result.matched.size + result.unmatched_payments.size,
          matched_payments: result.matched.size,
          discrepancies: result.discrepancies.size,
          unmatched_payments: result.unmatched_payments.size,
          unmatched_bank_records: result.unmatched_bank_records.size
        },
        details: {
          matched: result.matched,
          discrepancies: result.discrepancies,
          unmatched_payments: result.unmatched_payments.map { |p| p.slice(:id, :po_number, :amount, :payment_date) },
          unmatched_bank_records: result.unmatched_bank_records
        }
      }
    end

    private

    def fetch_bank_statement_records(start_date, end_date, agency_id)
      # Mock implementation - replace with actual bank API integration
      # For First Citizens Bank, Republic Bank, Scotiabank Trinidad, JMMB
      
      # In production, you would:
      # 1. Connect to each bank's API using their credentials
      # 2. Download statement for the date range
      # 3. Parse and normalize the data
      
      # Mock data for development
      [
        {
          date: start_date + 1.day,
          description: "VENDOR PAYMENT",
          amount: 1250.00,
          reference: "PO-20240115-001",
          bank_reference: "FCB-TXN-123456"
        },
        {
          date: start_date + 2.days,
          description: "SUPPLIER PAYMENT",
          amount: 850.75,
          reference: "PO-20240116-002",
          bank_reference: "RB-TXN-789012"
        }
      ]
    end

    def reconcile(payments, bank_records)
      matched = []
      discrepancies = []
      
      # Create lookup hashes
      payment_by_ref = payments.index_by(&:payment_reference)
      bank_record_by_ref = bank_records.index_by { |r| r[:reference] }
      
      # Find matches and discrepancies
      payments.each do |payment|
        bank_record = bank_record_by_ref[payment.po_number] || 
                     bank_record_by_ref[payment.payment_reference]
        
        if bank_record
          if payment.amount.to_f == bank_record[:amount].to_f
            matched << {
              purchase_order: payment,
              bank_record: bank_record,
              status: 'matched'
            }
          else
            discrepancies << {
              type: 'amount_mismatch',
              purchase_order: payment,
              bank_record: bank_record,
              payment_amount: payment.amount,
              bank_amount: bank_record[:amount],
              difference: (payment.amount - bank_record[:amount]).abs
            }
          end
        end
      end
      
      # Find unmatched items
      matched_payment_refs = matched.map { |m| m[:purchase_order].payment_reference }
      unmatched_payments = payments.reject { |p| matched_payment_refs.include?(p.payment_reference) }
      
      matched_bank_refs = matched.map { |m| m[:bank_record][:reference] }
      unmatched_bank_records = bank_records.reject { |r| matched_bank_refs.include?(r[:reference]) }
      
      ReconciliationResult.new(
        matched: matched,
        discrepancies: discrepancies,
        unmatched_payments: unmatched_payments,
        unmatched_bank_records: unmatched_bank_records
      )
    end

    def bank_confirmation_exists?(payment)
      # Check if we have a bank record for this payment
      # Mock implementation
      rand > 0.1 # 90% of payments have bank confirmation
    end

    def bank_amount_mismatch?(payment)
      # Check if payment amount matches bank amount
      # Mock implementation
      rand > 0.95 # 5% chance of mismatch
    end

    def bank_settlement_complete?(payment)
      # Check if bank has settled the transaction
      # Mock implementation
      payment.paid_at < 2.days.ago # Assume settled after 2 days
    end
  end
end