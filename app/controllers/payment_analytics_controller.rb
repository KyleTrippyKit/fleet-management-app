class PaymentAnalyticsController < ApplicationController
  before_action :authenticate_user!
  before_action :require_finance_or_admin, except: [:agency_dashboard]
  
  def index
    @time_range = params[:time_range] || '30_days'
    @agency_id = params[:agency_id]
    
    case @time_range
    when '7_days'
      @start_date = 7.days.ago
    when '30_days'
      @start_date = 30.days.ago
    when '90_days'
      @start_date = 90.days.ago
    when 'custom'
      @start_date = Date.parse(params[:start_date]) if params[:start_date].present?
      @end_date = Date.parse(params[:end_date]) if params[:end_date].present?
    end
    
    @start_date ||= 30.days.ago
    @end_date ||= Time.current
    
    @stats = PurchaseOrder.trinidad_payment_stats(
      time_range: @start_date..@end_date,
      agency_id: @agency_id
    )
    
    @agencies = Agency.all if current_user.admin?
  end
  
  def reconciliation
    @start_date = params[:start_date] || Date.current.beginning_of_month
    @end_date = params[:end_date] || Date.current
    @agency_id = params[:agency_id]
    
    @report = PaymentReconciliation.generate_reconciliation_report(
      start_date: @start_date,
      end_date: @end_date,
      agency_id: @agency_id
    )
    
    @discrepancies = PaymentReconciliation.find_discrepancies(agency_id: @agency_id)
    
    @agencies = Agency.all if current_user.admin?
  end
  
  def compliance
    @purchase_orders = PurchaseOrder
      .trinidad_card_payments
      .order(created_at: :desc)
      .page(params[:page]).per(20)
    
    if params[:agency_id].present?
      @purchase_orders = @purchase_orders.for_agency(params[:agency_id])
    end
    
    @agencies = Agency.all if current_user.admin?
  end
  
  def vendor_analysis
    @vendor = params[:vendor]
    
    if @vendor.present?
      @purchase_orders = PurchaseOrder
        .trinidad_card_payments
        .where(vendor: @vendor)
        .order(created_at: :desc)
        .page(params[:page]).per(20)
      
      @vendor_stats = {
        total_transactions: @purchase_orders.total_count,
        total_amount: @purchase_orders.sum(:amount),
        average_amount: @purchase_orders.average(:amount).to_f,
        first_transaction: @purchase_orders.minimum(:created_at),
        last_transaction: @purchase_orders.maximum(:created_at)
      }
    end
    
    # Top vendors
    @top_vendors = PurchaseOrder
      .trinidad_card_payments
      .group(:vendor)
      .order('sum_amount desc')
      .limit(10)
      .sum(:amount)
  end
  
  def export_reconciliation
    start_date = Date.parse(params[:start_date])
    end_date = Date.parse(params[:end_date])
    
    report = PaymentReconciliation.generate_reconciliation_report(
      start_date: start_date,
      end_date: end_date,
      agency_id: params[:agency_id]
    )
    
    respond_to do |format|
      format.csv do
        csv_data = CSV.generate(headers: true) do |csv|
          csv << ['Date', 'PO Number', 'Vendor', 'Amount', 'Status', 'Bank Reference', 'Match Status']
          
          report[:details][:matched].each do |match|
            csv << [
              match[:purchase_order].created_at.to_date,
              match[:purchase_order].po_number,
              match[:purchase_order].vendor,
              match[:purchase_order].amount,
              'Matched',
              match[:bank_record][:bank_reference],
              '✓'
            ]
          end
          
          report[:details][:unmatched_payments].each do |po|
            csv << [
              po.created_at.to_date,
              po.po_number,
              po.vendor,
              po.amount,
              'Unmatched',
              po.payment_reference,
              '✗'
            ]
          end
        end
        
        send_data csv_data, filename: "reconciliation-#{start_date}-to-#{end_date}.csv"
      end
      
      format.pdf do
        render pdf: "reconciliation-report-#{Date.today}",
               template: 'payment_analytics/reconciliation_pdf',
               layout: 'pdf'
      end
    end
  end
  
  private
  
  def require_finance_or_admin
    unless current_user.finance? || current_user.admin?
      redirect_to root_path, alert: 'Unauthorized - Finance or Admin access required'
    end
  end
end