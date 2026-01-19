# app/controllers/mock_data_controller.rb
class MockDataController < ApplicationController
  before_action :authenticate_user!
  before_action :check_demo_mode
  
  def generate_sale
    sale_data = generate_mock_sale(current_user.agency_id)
    
    # Create a mock POS transaction
    @transaction = PosTransaction.new(
      transaction_id: sale_data[:transaction_id],
      amount: sale_data[:total],
      payment_type: sale_data[:payment_method] == 'cash' ? 0 : 1,
      status: :completed,
      user: current_user,
      notes: "Mock sale generated for demo"
    )
    
    if @transaction.save
      render json: {
        success: true,
        message: 'Mock sale generated',
        transaction: @transaction,
        receipt: sale_data
      }
    else
      render json: {
        success: false,
        errors: @transaction.errors.full_messages
      }
    end
  end
  
  def sales_dashboard
    # Generate mock sales data for dashboard
    @sales_data = {
      today: {
        transactions: rand(10..50),
        amount: rand(1000..5000).to_f,
        average_ticket: rand(50..200).to_f
      },
      yesterday: {
        transactions: rand(5..40),
        amount: rand(500..4000).to_f,
        average_ticket: rand(40..180).to_f
      },
      week: {
        transactions: rand(50..200),
        amount: rand(5000..20000).to_f,
        average_ticket: rand(45..190).to_f
      }
    }
    
    @top_products = Array.new(5) do |i|
      {
        name: "Product #{i+1}",
        sales: rand(500..5000).to_f,
        quantity: rand(10..100)
      }
    end
    
    @payment_methods = [
      { method: 'Cash', percentage: 40, amount: rand(2000..10000).to_f },
      { method: 'Trinidad Debit Card', percentage: 35, amount: rand(1500..8000).to_f },
      { method: 'Trinidad Credit Card', percentage: 20, amount: rand(1000..5000).to_f },
      { method: 'Bank Transfer', percentage: 5, amount: rand(200..1000).to_f }
    ]
    
    render json: {
      sales_data: @sales_data,
      top_products: @top_products,
      payment_methods: @payment_methods
    }
  end
  
  def process_payment
    # Mock payment processing
    sleep rand(1..3) if Rails.env.development? # Simulate processing delay
    
    render json: {
      success: true,
      message: 'Payment processed successfully (Demo)',
      transaction_id: "MOCK-#{Time.current.to_i}-#{SecureRandom.hex(4)}",
      timestamp: Time.current.iso8601,
      bank_response: {
        bank: 'First Citizens Bank (Demo)',
        authorization_code: SecureRandom.alphanumeric(6).upcase,
        reference: "DEMO-#{SecureRandom.hex(4).upcase}"
      }
    }
  end
  
  def inventory_report
    agency_id = current_user.agency_id
    
    @inventory_summary = {
      total_products: rand(50..200),
      total_value: rand(50000..200000).to_f,
      low_stock: rand(5..20),
      out_of_stock: rand(0..5),
      categories: [
        { name: 'Vehicle Parts', count: rand(5..15), value: rand(5000..30000).to_f },
        { name: 'Maintenance Services', count: rand(3..10), value: rand(10000..50000).to_f },
        { name: 'Fuel & Lubricants', count: rand(8..20), value: rand(8000..40000).to_f },
        { name: 'Tires & Wheels', count: rand(2..8), value: rand(3000..15000).to_f }
      ]
    }
    
    @reorder_list = Array.new(rand(3..8)) do
      {
        product_id: rand(1..50),
        name: "Product #{SecureRandom.hex(4)}",
        current_stock: rand(0..10),
        reorder_level: rand(5..15),
        last_order_date: (Time.current - rand(7..30).days).strftime('%Y-%m-%d')
      }
    end
    
    render json: {
      summary: @inventory_summary,
      reorder_list: @reorder_list
    }
  end
  
  def terminal
    # Show POS terminal interface
    render layout: 'terminal'
  end
  
  def simulate_sale
    # Simulate a POS sale
    items = params[:items] || []
    payment_method = params[:payment_method] || 'cash'
    amount_tendered = params[:amount_tendered].to_f
    
    # Calculate totals
    subtotal = items.sum { |item| item[:quantity].to_i * item[:price].to_f }
    tax = subtotal * 0.125  # Trinidad VAT
    total = subtotal + tax
    
    change_due = 0
    if payment_method == 'cash' && amount_tendered > 0
      change_due = amount_tendered - total
    end
    
    transaction_id = "DEMO-POS-#{Time.current.strftime('%Y%m%d')}-#{SecureRandom.hex(4).upcase}"
    
    render json: {
      success: true,
      transaction_id: transaction_id,
      receipt: {
        transaction_id: transaction_id,
        items: items,
        subtotal: subtotal.round(2),
        tax: tax.round(2),
        total: total.round(2),
        payment_method: payment_method,
        amount_tendered: amount_tendered,
        change_due: change_due > 0 ? change_due.round(2) : 0,
        timestamp: Time.current.iso8601
      }
    }
  end
  
  # NEW: Mock Purchase Order Payment Methods
  
  def simulate_purchase_order_payment
    # Simulate a Trinidad card payment for a purchase order
    po_number = params[:po_number] || "PO-#{Time.current.strftime('%Y%m%d')}-#{rand(100..999)}"
    amount = params[:amount].to_f || rand(100..5000).to_f
    card_type = params[:card_type] || ['debit', 'credit'].sample
    bank = params[:bank] || ['First Citizens Bank', 'Republic Bank', 'Scotiabank', 'JMMB'].sample
    
    # Simulate processing delay
    sleep rand(1..3) if Rails.env.development?
    
    # Simulate random failures (10% chance)
    if rand < 0.1
      render json: {
        success: false,
        message: 'Payment declined by bank',
        error_code: ['INSUFFICIENT_FUNDS', 'INVALID_CARD', 'DECLINED', 'EXPIRED_CARD'].sample,
        po_number: po_number,
        amount: amount,
        timestamp: Time.current.iso8601
      }, status: :unprocessable_entity
    else
      transaction_id = "DEMO-PO-#{po_number}-#{SecureRandom.hex(8).upcase}"
      
      render json: {
        success: true,
        message: 'Purchase order payment processed successfully (Demo)',
        transaction_id: transaction_id,
        po_number: po_number,
        amount: amount,
        payment_method: "trinidad_#{card_type}_card",
        card_type: card_type == 'debit' ? 'visa_debit' : 'mastercard',
        last_four_digits: rand(1000..9999).to_s,
        bank: bank,
        authorization_code: SecureRandom.alphanumeric(6).upcase,
        timestamp: Time.current.iso8601,
        bank_response: {
          status: 'pending',
          message: 'Transaction authorized, pending settlement',
          bank_reference: "BANK-REF-#{SecureRandom.alphanumeric(12).upcase}"
        }
      }
    end
  end
  
  def purchase_order_payment_status
    # Check payment status for a purchase order
    transaction_id = params[:transaction_id]
    po_number = params[:po_number]
    
    # Mock different statuses based on time
    statuses = ['pending', 'authorized', 'processing', 'completed', 'failed']
    status = statuses.sample
    
    render json: {
      transaction_id: transaction_id,
      po_number: po_number,
      status: status,
      timestamp: Time.current.iso8601,
      details: {
        initiated_at: (Time.current - rand(1..10).minutes).iso8601,
        last_updated: Time.current.iso8601,
        settlement_estimated: status == 'processing' ? (Time.current + rand(1..24).hours).iso8601 : nil
      }
    }
  end
  
  def simulate_payment_authorization
    # Simulate payment authorization (for supervisor approval)
    po_number = params[:po_number]
    amount = params[:amount].to_f || rand(500..10000).to_f
    user_name = current_user.name
    
    render json: {
      success: true,
      message: 'Payment authorized successfully (Demo)',
      po_number: po_number,
      amount: amount,
      authorized_by: user_name,
      authorization_code: "AUTH-#{SecureRandom.alphanumeric(8).upcase}",
      timestamp: Time.current.iso8601,
      compliance_check: {
        passed: true,
        violations: [],
        requires_approval: false,
        notes: 'All compliance checks passed'
      }
    }
  end
  
  def simulate_payment_completion
    # Simulate payment completion/settlement
    po_number = params[:po_number]
    transaction_id = params[:transaction_id]
    
    render json: {
      success: true,
      message: 'Payment completed successfully (Demo)',
      po_number: po_number,
      transaction_id: transaction_id,
      settlement_date: Date.today.to_s,
      settlement_reference: "SETTLE-#{SecureRandom.alphanumeric(10).upcase}",
      timestamp: Time.current.iso8601,
      invoice_generated: true,
      invoice_number: "INV-#{po_number}",
      details: {
        processing_time: "#{rand(1..60)} minutes",
        bank_confirmation: true,
        funds_transferred: true
      }
    }
  end
  
  def mock_payment_reconciliation
    # Generate mock reconciliation report
    start_date = params[:start_date] || Date.today.beginning_of_month.to_s
    end_date = params[:end_date] || Date.today.to_s
    agency_id = params[:agency_id] || current_user.agency_id
    
    report_data = {
      report_period: { start_date: start_date, end_date: end_date },
      generated_at: Time.current.iso8601,
      summary: {
        total_transactions: rand(50..200),
        total_amount: rand(50000..200000).to_f,
        matched_payments: rand(40..180),
        unmatched_payments: rand(5..20),
        discrepancies: rand(0..5),
        reconciliation_status: ['complete', 'pending', 'in_progress'].sample
      },
      bank_transactions: Array.new(rand(5..15)) do |i|
        {
          date: (Date.today - rand(0..30).days).to_s,
          description: ['VENDOR PAYMENT', 'SUPPLIER PAYMENT', 'PO PAYMENT', 'INVOICE PAYMENT'].sample,
          amount: rand(100..5000).to_f,
          reference: "PO-#{Date.today.strftime('%Y%m%d')}-#{rand(100..999)}",
          bank_reference: "BANK-#{SecureRandom.alphanumeric(10).upcase}",
          status: ['matched', 'unmatched', 'pending'].sample
        }
      end,
      discrepancies: Array.new(rand(0..3)) do
        {
          type: ['amount_mismatch', 'missing_payment', 'duplicate_payment', 'date_mismatch'].sample,
          po_number: "PO-#{Date.today.strftime('%Y%m%d')}-#{rand(100..999)}",
          amount: rand(100..2000).to_f,
          difference: rand(10..500).to_f,
          status: ['resolved', 'pending', 'investigating'].sample
        }
      end
    }
    
    render json: report_data
  end
  
  def mock_payment_analytics
    # Generate mock payment analytics
    time_range = params[:time_range] || '30_days'
    agency_id = params[:agency_id] || current_user.agency_id
    
    analytics_data = {
      period: time_range,
      generated_at: Time.current.iso8601,
      summary: {
        total_transactions: rand(100..500),
        total_amount: rand(100000..500000).to_f,
        average_amount: rand(500..2000).to_f,
        success_rate: rand(85..99).to_f.round(2)
      },
      breakdown: {
        by_payment_method: [
          { method: 'Trinidad Credit Card', count: rand(30..100), amount: rand(30000..150000).to_f, percentage: rand(25..40) },
          { method: 'Trinidad Debit Card', count: rand(40..120), amount: rand(40000..180000).to_f, percentage: rand(30..45) },
          { method: 'Bank Transfer', count: rand(10..40), amount: rand(10000..50000).to_f, percentage: rand(5..15) },
          { method: 'Cash', count: rand(5..30), amount: rand(5000..25000).to_f, percentage: rand(2..10) }
        ],
        by_bank: [
          { bank: 'First Citizens Bank', count: rand(20..80), amount: rand(20000..100000).to_f },
          { bank: 'Republic Bank', count: rand(15..70), amount: rand(15000..90000).to_f },
          { bank: 'Scotiabank', count: rand(10..50), amount: rand(10000..60000).to_f },
          { bank: 'JMMB Bank', count: rand(5..30), amount: rand(5000..30000).to_f }
        ],
        by_vendor: Array.new(rand(5..10)) do |i|
          {
            vendor: ["AutoParts Trinidad", "TT Motors", "Caribbean Spares", "Trinidad Maintenance", "Island Auto"].sample,
            count: rand(5..30),
            amount: rand(5000..50000).to_f
          }
        end.uniq { |v| v[:vendor] }
      },
      trends: {
        daily_volume: (0..29).map do |days_ago|
          date = Date.today - days_ago.days
          {
            date: date.to_s,
            count: rand(1..10),
            amount: rand(1000..10000).to_f
          }
        end.reverse,
        success_rate_trend: (0..11).map do |month|
          {
            month: (Date.today - month.months).strftime('%Y-%m'),
            rate: rand(80..99).to_f.round(2)
          }
        end.reverse
      }
    }
    
    render json: analytics_data
  end
  
  def mock_compliance_check
    # Simulate compliance check for a purchase order
    po_number = params[:po_number]
    amount = params[:amount].to_f || rand(100..50000).to_f
    vendor = params[:vendor] || ['AutoParts Trinidad', 'TT Motors', 'Caribbean Spares'].sample
    
    # Randomly generate compliance issues (30% chance)
    has_issues = rand < 0.3
    
    compliance_report = {
      po_number: po_number,
      checked_at: Time.current.iso8601,
      amount: amount,
      vendor: vendor,
      result: {
        compliant: !has_issues,
        requires_approval: has_issues,
        violation_count: has_issues ? rand(1..3) : 0,
        warning_count: rand(0..2)
      },
      details: {
        violations: has_issues ? [
          {
            code: 'TRANSACTION_LIMIT_EXCEEDED',
            message: "Amount (TTD #{amount}) exceeds single transaction limit (TTD 50000)",
            severity: 'high'
          },
          {
            code: 'DAILY_LIMIT_WARNING',
            message: "Approaching daily transaction limit for agency",
            severity: 'medium'
          }
        ].take(rand(1..2)) : [],
        warnings: [
          {
            code: 'HIGH_RISK_VENDOR',
            message: "Vendor has been flagged for review",
            severity: 'low'
          }
        ].take(rand(0..1)),
        recommendations: has_issues ? [
          "Requires additional approval from finance supervisor",
          "Consider splitting transaction into multiple payments"
        ] : ["All compliance checks passed"]
      }
    }
    
    render json: compliance_report
  end
  
  def mock_payment_audit_trail
    # Generate mock payment audit trail
    po_number = params[:po_number] || "PO-#{Time.current.strftime('%Y%m%d')}-#{rand(100..999)}"
    
    actions = [
      { action: 'initiated', user: 'Finance Clerk', timestamp: (Time.current - 4.hours).iso8601 },
      { action: 'validated', user: 'System', timestamp: (Time.current - 3.hours + 30.minutes).iso8601 },
      { action: 'compliance_checked', user: 'Compliance System', timestamp: (Time.current - 3.hours).iso8601 },
      { action: 'authorized', user: 'Supervisor', timestamp: (Time.current - 2.hours).iso8601 },
      { action: 'bank_processing', user: 'Bank System', timestamp: (Time.current - 1.hour).iso8601 },
      { action: 'completed', user: 'System', timestamp: Time.current.iso8601 }
    ]
    
    # Randomly select some actions to include
    selected_actions = actions.sample(rand(3..6)).sort_by { |a| Time.parse(a[:timestamp]) }
    
    audit_trail = {
      po_number: po_number,
      audit_count: selected_actions.count,
      actions: selected_actions.map.with_index do |action, index|
        {
          id: index + 1,
          action: action[:action],
          user: action[:user],
          timestamp: action[:timestamp],
          metadata: {
            ip_address: index.even? ? '192.168.1.' + rand(1..255).to_s : '10.0.0.' + rand(1..255).to_s,
            duration_from_previous: index > 0 ? rand(300..3600) : nil, # 5-60 minutes
            notes: generate_audit_notes(action[:action])
          }
        }
      end
    }
    
    render json: audit_trail
  end
  
  def mock_trinidad_card_payment_flow
    # Complete mock Trinidad card payment flow
    po_number = params[:po_number] || "PO-#{Time.current.strftime('%Y%m%d')}-#{rand(100..999)}"
    amount = params[:amount].to_f || rand(500..5000).to_f
    
    flow_data = {
      po_number: po_number,
      amount: amount,
      flow_steps: [
        {
          step: 1,
          name: 'Payment Initiation',
          status: 'completed',
          timestamp: (Time.current - 4.hours).iso8601,
          details: {
            card_type: 'Trinidad Visa Debit',
            last_four: rand(1000..9999).to_s,
            bank: 'First Citizens Bank',
            reference: "TXN-#{SecureRandom.hex(8).upcase}"
          }
        },
        {
          step: 2,
          name: 'Card Validation',
          status: 'completed',
          timestamp: (Time.current - 3.hours + 45.minutes).iso8601,
          details: {
            validation_result: 'valid',
            card_network: 'Visa',
            country: 'Trinidad and Tobago'
          }
        },
        {
          step: 3,
          name: 'Compliance Check',
          status: 'completed',
          timestamp: (Time.current - 3.hours + 30.minutes).iso8601,
          details: {
            result: 'passed',
            violations: [],
            requires_approval: false
          }
        },
        {
          step: 4,
          name: 'Bank Authorization',
          status: 'pending',
          timestamp: nil,
          details: {
            expected_time: (Time.current + 30.minutes).iso8601,
            authorization_required: true
          }
        },
        {
          step: 5,
          name: 'Settlement Processing',
          status: 'pending',
          timestamp: nil,
          details: {
            estimated_settlement: (Time.current + 2.hours).iso8601
          }
        },
        {
          step: 6,
          name: 'Invoice Generation',
          status: 'pending',
          timestamp: nil,
          details: {
            auto_generate: true
          }
        }
      ],
      current_step: 4,
      overall_status: 'pending_authorization',
      estimated_completion: (Time.current + 3.hours).iso8601
    }
    
    render json: flow_data
  end
  
  private
  
  def generate_mock_sale(agency_id)
    {
      transaction_id: "SALE-#{Time.current.strftime('%Y%m%d')}-#{SecureRandom.hex(4).upcase}",
      items: Array.new(rand(1..5)) do
        {
          product_id: rand(1..50),
          name: ["Oil Change", "Brake Pads", "Tire Rotation", "Engine Filter", "Battery"].sample,
          quantity: rand(1..3),
          price: rand(20..500).to_f
        }
      end,
      subtotal: rand(100..1000).to_f,
      tax: rand(10..100).to_f,
      total: rand(110..1100).to_f,
      payment_method: ['cash', 'trinidad_debit_card', 'trinidad_credit_card', 'bank_transfer'].sample,
      timestamp: Time.current - rand(0..24).hours
    }
  end
  
  def generate_audit_notes(action)
    case action
    when 'initiated'
      "Payment initiated via Trinidad card payment gateway"
    when 'authorized'
      "Payment authorized by supervisor with compliance approval"
    when 'completed'
      "Payment completed and settled with bank. Invoice auto-generated."
    when 'failed'
      "Payment failed: Bank declined transaction"
    when 'compliance_checked'
      "Compliance check completed - all requirements met"
    else
      "System action performed"
    end
  end
  
  def check_demo_mode
    unless Rails.env.development? || Rails.env.test? || ENV['DEMO_MODE'] == 'true'
      render json: { error: 'Mock features only available in demo mode' }, status: :forbidden
    end
  end
end