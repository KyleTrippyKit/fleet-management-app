# app/models/concerns/purchase_order_analytics.rb
module PurchaseOrderAnalytics
  extend ActiveSupport::Concern
  
  included do
    scope :trinidad_card_payments, -> { 
      where(payment_method: ['trinidad_credit_card', 'trinidad_debit_card']) 
    }
    
    scope :successful_trinidad_payments, -> {
      trinidad_card_payments.where(payment_status: 'completed')
    }
    
    scope :failed_trinidad_payments, -> {
      trinidad_card_payments.where(payment_status: 'failed')
    }
    
    scope :pending_trinidad_payments, -> {
      trinidad_card_payments.where(payment_status: ['pending', 'processing', 'authorized'])
    }
  end
  
  module ClassMethods
    def trinidad_payment_stats(time_range: 30.days.ago..Time.current, agency_id: nil)
      payments = trinidad_card_payments
        .where(created_at: time_range)
        .order(created_at: :asc)
      
      payments = payments.for_agency(agency_id) if agency_id.present?
      
      successful = payments.successful_trinidad_payments
      failed = payments.failed_trinidad_payments
      pending = payments.pending_trinidad_payments
      total_count = payments.count
      
      {
        summary: {
          total_transactions: total_count,
          total_amount: payments.sum(:amount),
          successful_count: successful.count,
          failed_count: failed.count,
          pending_count: pending.count
        },
        amounts: {
          total_successful_amount: successful.sum(:amount),
          average_successful_amount: successful.average(:amount).to_f,
          max_successful_amount: successful.maximum(:amount).to_f,
          min_successful_amount: successful.minimum(:amount).to_f
        },
        rates: {
          success_rate: total_count > 0 ? (successful.count.to_f / total_count * 100).round(2) : 0,
          failure_rate: total_count > 0 ? (failed.count.to_f / total_count * 100).round(2) : 0,
          pending_rate: total_count > 0 ? (pending.count.to_f / total_count * 100).round(2) : 0
        },
        timing: {
          average_processing_time: average_processing_time(successful),
          fastest_payment: fastest_payment(successful),
          slowest_payment: slowest_payment(successful)
        },
        breakdown: {
          by_bank: bank_breakdown(payments),
          by_card_type: card_type_breakdown(payments),
          by_vendor: vendor_breakdown(payments),
          by_day_of_week: day_of_week_breakdown(payments),
          by_hour: hour_breakdown(payments)
        },
        trends: {
          daily_volume: daily_volume_trend(payments, time_range),
          weekly_totals: weekly_totals_trend(payments, time_range),
          monthly_comparison: monthly_comparison(payments)
        }
      }
    end
    
    def bank_breakdown(payments)
      # Analyze by inferred bank (based on card BIN)
      breakdown = Hash.new(0)
      
      payments.find_each do |payment|
        bank = infer_bank_from_payment(payment)
        breakdown[bank] += 1
      end
      
      breakdown.sort_by { |_, count| -count }.to_h
    end
    
    def card_type_breakdown(payments)
      payments.group(:payment_method).count.transform_keys do |method|
        method.gsub('trinidad_', '').humanize.titleize
      end
    end
    
    def vendor_breakdown(payments, limit: 10)
      payments
        .group(:vendor)
        .order('count_all desc')
        .limit(limit)
        .count
    end
    
    def day_of_week_breakdown(payments)
      breakdown = Hash.new(0)
      
      payments.each do |payment|
        day = payment.created_at.strftime('%A')
        breakdown[day] += 1
      end
      
      # Ensure all days are present
      Date::DAYNAMES.each do |day|
        breakdown[day] ||= 0
      end
      
      breakdown.sort_by { |day, _| Date::DAYNAMES.index(day) }.to_h
    end
    
    def hour_breakdown(payments)
      breakdown = Hash.new(0)
      
      payments.each do |payment|
        hour = payment.created_at.hour
        breakdown[hour] += 1
      end
      
      # Ensure all hours are present
      (0..23).each do |hour|
        breakdown[hour] ||= 0
      end
      
      breakdown.sort_by { |hour, _| hour }.to_h
    end
    
    def daily_volume_trend(payments, time_range)
      trend = {}
      
      current_date = time_range.begin.to_date
      end_date = time_range.end.to_date
      
      while current_date <= end_date
        count = payments.where(
          created_at: current_date.beginning_of_day..current_date.end_of_day
        ).count
        
        trend[current_date.to_s] = {
          date: current_date.to_s,
          count: count,
          amount: payments.where(
            created_at: current_date.beginning_of_day..current_date.end_of_day
          ).sum(:amount)
        }
        
        current_date += 1.day
      end
      
      trend
    end
    
    def weekly_totals_trend(payments, time_range)
      trend = {}
      
      payments.group_by_week(:created_at, range: time_range).count.each do |week, count|
        trend[week.to_s] = {
          week: week.to_s,
          count: count,
          amount: payments.where(created_at: week).sum(:amount)
        }
      end
      
      trend
    end
    
    def monthly_comparison(payments)
      comparison = {}
      
      payments.group_by_month(:created_at).count.each do |month, count|
        comparison[month.strftime('%Y-%m')] = {
          month: month.strftime('%B %Y'),
          count: count,
          amount: payments.where(created_at: month.beginning_of_month..month.end_of_month).sum(:amount),
          average_amount: payments.where(created_at: month.beginning_of_month..month.end_of_month).average(:amount).to_f
        }
      end
      
      comparison
    end
    
    private
    
    def average_processing_time(successful_payments)
      return 0 if successful_payments.empty?
      
      total_seconds = successful_payments.sum do |payment|
        next 0 unless payment.payment_initiated_at && payment.paid_at
        
        (payment.paid_at - payment.payment_initiated_at).to_i
      end
      
      (total_seconds / successful_payments.count.to_f).round(2)
    end
    
    def fastest_payment(successful_payments)
      return nil if successful_payments.empty?
      
      successful_payments.min_by do |payment|
        next Float::INFINITY unless payment.payment_initiated_at && payment.paid_at
        
        (payment.paid_at - payment.payment_initiated_at).to_i
      end
    end
    
    def slowest_payment(successful_payments)
      return nil if successful_payments.empty?
      
      successful_payments.max_by do |payment|
        next 0 unless payment.payment_initiated_at && payment.paid_at
        
        (payment.paid_at - payment.payment_initiated_at).to_i
      end
    end
    
    def infer_bank_from_payment(payment)
      # Infer bank from payment details
      if payment.last_four_digits
        # Simple inference based on common patterns
        case payment.last_four_digits[0].to_i
        when 4
          'First Citizens Bank'
        when 5
          'Republic Bank'
        when 3
          'Scotiabank Trinidad'
        else
          'Other Trinidad Bank'
        end
      else
        'Unknown Bank'
      end
    end
  end
end