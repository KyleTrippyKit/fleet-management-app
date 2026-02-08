# app/services/trinidad_compliance_checker.rb
class TrinidadComplianceChecker
  # Central Bank of Trinidad and Tobago guidelines
  MAX_SINGLE_TRANSACTION = 50_000.00 # TTD
  DAILY_TRANSACTION_LIMIT = 150_000.00 # TTD
  MONTHLY_AGENCY_LIMIT = 1_000_000.00 # TTD
  
  ComplianceResult = Struct.new(:compliant, :violations, :warnings, :requires_approval, keyword_init: true)
  
  class << self
    def check_compliance(purchase_order)
      violations = []
      warnings = []
      requires_approval = false
      
      # Check transaction limits
      if purchase_order.amount > MAX_SINGLE_TRANSACTION
        violations << {
          code: 'TRANSACTION_LIMIT_EXCEEDED',
          message: "Amount (TTD #{purchase_order.amount}) exceeds single transaction limit (TTD #{MAX_SINGLE_TRANSACTION})",
          severity: 'high'
        }
        requires_approval = true
      end
      
      # Check daily limits for agency
      if purchase_order.agency_id
        daily_total = daily_agency_total(purchase_order.agency_id, purchase_order.created_at || Time.current)
        
        if (daily_total + purchase_order.amount) > DAILY_TRANSACTION_LIMIT
          violations << {
            code: 'DAILY_LIMIT_EXCEEDED',
            message: "Would exceed daily transaction limit for agency (current: TTD #{daily_total}, limit: TTD #{DAILY_TRANSACTION_LIMIT})",
            severity: 'high'
          }
          requires_approval = true
        end
      end
      
      # Check monthly limits
      if purchase_order.agency_id
        monthly_total = monthly_agency_total(purchase_order.agency_id, purchase_order.created_at || Time.current)
        
        if (monthly_total + purchase_order.amount) > MONTHLY_AGENCY_LIMIT
          warnings << {
            code: 'MONTHLY_LIMIT_WARNING',
            message: "Approaching monthly transaction limit (current: TTD #{monthly_total}, limit: TTD #{MONTHLY_AGENCY_LIMIT})",
            severity: 'medium'
          }
        end
      end
      
      # Check for suspicious patterns
      suspicious_patterns = check_suspicious_patterns(purchase_order)
      if suspicious_patterns.any?
        suspicious_patterns.each do |pattern|
          violations << pattern.merge(severity: 'critical')
        end
        requires_approval = true
      end
      
      # Check vendor risk
      vendor_risk = check_vendor_risk(purchase_order.vendor)
      if vendor_risk[:high_risk]
        warnings << {
          code: 'HIGH_RISK_VENDOR',
          message: "Vendor '#{purchase_order.vendor}' has been flagged for review",
          severity: 'medium'
        }
      end
      
      # Check time-based restrictions (business hours)
      unless within_business_hours?(purchase_order.created_at || Time.current)
        warnings << {
          code: 'OUTSIDE_BUSINESS_HOURS',
          message: "Transaction initiated outside normal business hours (8:00 AM - 6:00 PM)",
          severity: 'low'
        }
      end
      
      ComplianceResult.new(
        compliant: violations.empty?,
        violations: violations,
        warnings: warnings,
        requires_approval: requires_approval
      )
    end
    
    def pre_approval_required?(purchase_order)
      result = check_compliance(purchase_order)
      result.requires_approval || result.violations.any? { |v| v[:severity] == 'critical' }
    end
    
    def generate_compliance_report(purchase_order)
      result = check_compliance(purchase_order)
      
      {
        purchase_order_id: purchase_order.id,
        po_number: purchase_order.po_number,
        vendor: purchase_order.vendor,
        amount: purchase_order.amount,
        agency: purchase_order.agency&.name,
        check_performed_at: Time.current.iso8601,
        result: {
          compliant: result.compliant,
          requires_approval: result.requires_approval,
          violation_count: result.violations.count,
          warning_count: result.warnings.count
        },
        details: {
          violations: result.violations,
          warnings: result.warnings
        },
        limits: {
          single_transaction: MAX_SINGLE_TRANSACTION,
          daily_agency_limit: DAILY_TRANSACTION_LIMIT,
          monthly_agency_limit: MONTHLY_AGENCY_LIMIT
        },
        recommendations: generate_recommendations(result)
      }
    end
    
    private
    
    def daily_agency_total(agency_id, date)
      PurchaseOrder
        .for_agency(agency_id)
        .where(payment_method: ['trinidad_credit_card', 'trinidad_debit_card'])
        .where(created_at: date.beginning_of_day..date.end_of_day)
        .sum(:amount)
    end
    
    def monthly_agency_total(agency_id, date)
      PurchaseOrder
        .for_agency(agency_id)
        .where(payment_method: ['trinidad_credit_card', 'trinidad_debit_card'])
        .where(created_at: date.beginning_of_month..date.end_of_month)
        .sum(:amount)
    end
    
    def check_suspicious_patterns(purchase_order)
      patterns = []
      
      # 1. Round number amounts
      if purchase_order.amount.to_i == purchase_order.amount && purchase_order.amount >= 5000
        patterns << {
          code: 'ROUND_AMOUNT',
          message: "Round amount (TTD #{purchase_order.amount}) may require additional verification"
        }
      end
      
      # 2. Rapid successive transactions
      if rapid_successive_transactions?(purchase_order)
        patterns << {
          code: 'RAPID_SUCCESSIVE_TRANSACTIONS',
          message: "Multiple transactions in short time frame detected"
        }
      end
      
      # 3. Unusual vendor amount
      if unusual_vendor_amount?(purchase_order)
        patterns << {
          code: 'UNUSUAL_VENDOR_AMOUNT',
          message: "Amount is unusually high for this vendor"
        }
      end
      
      # 4. Outside normal vendor category
      if outside_vendor_category?(purchase_order)
        patterns << {
          code: 'OUTSIDE_VENDOR_CATEGORY',
          message: "Transaction category differs from vendor's typical purchases"
        }
      end
      
      patterns
    end
    
    def rapid_successive_transactions?(purchase_order)
      return false unless purchase_order.agency_id
      
      recent_transactions = PurchaseOrder
        .for_agency(purchase_order.agency_id)
        .where(payment_method: ['trinidad_credit_card', 'trinidad_debit_card'])
        .where('created_at > ?', 1.hour.ago)
        .count
      
      recent_transactions >= 3
    end
    
    def unusual_vendor_amount?(purchase_order)
      vendor_avg = PurchaseOrder
        .where(vendor: purchase_order.vendor)
        .where(payment_method: ['trinidad_credit_card', 'trinidad_debit_card'])
        .average(:amount)
        .to_f
      
      return false if vendor_avg == 0
      
      # Flag if amount is more than 3x the average
      purchase_order.amount > (vendor_avg * 3)
    end
    
    def outside_vendor_category?(purchase_order)
      # This would require vendor categorization data
      # For now, return false
      false
    end
    
    def check_vendor_risk(vendor_name)
      # Check vendor against risk database
      # Mock implementation
      {
        high_risk: false,
        risk_score: 0.1,
        last_reviewed: 30.days.ago
      }
    end
    
    def within_business_hours?(time)
      # Trinidad business hours: 8 AM to 6 PM
      hour = time.hour
      hour >= 8 && hour < 18
    end
    
    def generate_recommendations(result)
      recommendations = []
      
      if result.requires_approval
        recommendations << "Requires additional approval from finance supervisor"
      end
      
      if result.violations.any? { |v| v[:code] == 'TRANSACTION_LIMIT_EXCEEDED' }
        recommendations << "Consider splitting transaction into multiple payments"
      end
      
      if result.violations.any? { |v| v[:code] == 'DAILY_LIMIT_EXCEEDED' }
        recommendations << "Schedule payment for next business day"
      end
      
      if result.warnings.any? { |w| w[:code] == 'HIGH_RISK_VENDOR' }
        recommendations << "Verify vendor credentials and purchase justification"
      end
      
      recommendations
    end
  end
end