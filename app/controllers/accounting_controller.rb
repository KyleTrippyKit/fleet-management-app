require "csv"

class AccountingController < ApplicationController
  before_action :authenticate_user!
  before_action :require_finance!

  # =========================
  # GENERAL LEDGER
  # =========================
  def general_ledger
    @date_from   = parse_date(params[:date_from]) || Date.current.beginning_of_month
    @date_to     = parse_date(params[:date_to])   || Date.current.end_of_month
    @account_code = params[:account_code].presence

    scope = base_ledger_scope
      .where(entry_date: @date_from..@date_to)
      .order(:entry_date, :id)

    scope = scope.where(account_code: @account_code) if @account_code

    @entries = scope.includes(:invoice, :vehicle)

    @accounts = base_ledger_scope
      .select(:account_code, :account_name)
      .distinct
      .order(:account_code)

    @totals = {
      debit:  @entries.sum(&:debit),
      credit: @entries.sum(&:credit)
    }
  end

  # =========================
  # TRIAL BALANCE
  # =========================
  def trial_balance
    @date_from = parse_date(params[:date_from]) || Date.current.beginning_of_month
    @date_to   = parse_date(params[:date_to])   || Date.current.end_of_month

    @trial_rows, @grand_totals =
      build_trial_balance(@date_from, @date_to)

    respond_to do |format|
      format.html

      format.csv do
        send_data(
          trial_balance_csv(@trial_rows, @grand_totals),
          filename: "trial-balance-#{@date_from}-to-#{@date_to}.csv",
          type: "text/csv"
        )
      end

      format.pdf do
        render pdf: "trial-balance-#{@date_from}-to-#{@date_to}",
               template: "accounting/trial_balance_pdf",
               layout: "pdf",
               page_size: "A4",
               disposition: "inline"
      end
    end
  end

  private

  # =========================
  # AUTH
  # =========================
  def require_finance!
    unless current_user.finance? || current_user.admin?
      redirect_to root_path, alert: "Not authorized."
    end
  end

  # =========================
  # DATE PARSING
  # =========================
  def parse_date(value)
    return nil if value.blank?
    Date.parse(value)
  rescue ArgumentError
    nil
  end

  # =========================
  # AGENCY SCOPING
  # =========================
  # Agencies see their own data
  # VMCOTT + Admin see global
  def base_ledger_scope
    scope = LedgerEntry.all

    if current_user.agency&.code != "VMCOTT" && current_user.agency_id.present?
      scope = scope.where(agency_id: current_user.agency_id)
    end

    scope
  end

  # =========================
  # TRIAL BALANCE CORE LOGIC
  # =========================
  def build_trial_balance(date_from, date_to)
    rows = base_ledger_scope
      .where(entry_date: date_from..date_to)
      .group(:account_code, :account_name)
      .select(
        :account_code,
        :account_name,
        "COALESCE(SUM(debit), 0)  AS total_debit",
        "COALESCE(SUM(credit), 0) AS total_credit"
      )
      .order(:account_code)

    trial_rows = rows.map do |r|
      debit   = r.total_debit.to_f.round(2)
      credit  = r.total_credit.to_f.round(2)
      balance = (debit - credit).round(2) # debit-positive convention

      {
        account_code: r.account_code,
        account_name: r.account_name,
        total_debit:  debit,
        total_credit: credit,
        balance:      balance
      }
    end

    grand_debit  = trial_rows.sum { |x| x[:total_debit] }.round(2)
    grand_credit = trial_rows.sum { |x| x[:total_credit] }.round(2)

    grand_totals = {
      debit:     grand_debit,
      credit:    grand_credit,
      balanced?: (grand_debit - grand_credit).abs < 0.01
    }

    [trial_rows, grand_totals]
  end

  # =========================
  # CSV EXPORT
  # =========================
  def trial_balance_csv(trial_rows, grand_totals)
    CSV.generate(headers: true) do |csv|
      csv << ["Account Code", "Account Name", "Debit", "Credit", "Balance"]

      trial_rows.each do |r|
        csv << [
          r[:account_code],
          r[:account_name],
          r[:total_debit],
          r[:total_credit],
          r[:balance]
        ]
      end

      csv << []
      csv << [
        "TOTALS",
        "",
        grand_totals[:debit],
        grand_totals[:credit],
        (grand_totals[:debit] - grand_totals[:credit]).round(2)
      ]
      csv << [
        "BALANCED?",
        "",
        grand_totals[:balanced?] ? "YES" : "NO",
        "",
        ""
      ]
    end
  end
end
