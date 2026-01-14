<%# app/views/invoices/payment_history.html.erb %>
<div class="container-fluid mt-4">
  <div class="d-flex justify-content-between align-items-center mb-4">
    <div>
      <h1 class="h2 mb-1">Payment History</h1>
      <p class="text-muted mb-0">Invoice #<%= @invoice.invoice_number %> - <%= @invoice.vendor %></p>
    </div>
    <div>
      <%= link_to 'Back to Invoice', @invoice, class: 'btn btn-outline-secondary me-2' %>
      <%= link_to 'Record New Payment', new_transaction_path(invoice_id: @invoice.id), class: 'btn btn-primary' %>
    </div>
  </div>

  <%# Invoice Summary Card %>
  <div class="row mb-4">
    <div class="col-md-12">
      <div class="card">
        <div class="card-body">
          <div class="row">
            <div class="col-md-3">
              <h6 class="text-muted">Invoice Amount</h6>
              <h3 class="mb-0">$<%= number_with_precision(@invoice.amount, precision: 2) %></h3>
            </div>
            <div class="col-md-3">
              <h6 class="text-muted">Total Paid</h6>
              <h3 class="mb-0 text-success">$<%= number_with_precision(@invoice.total_paid, precision: 2) %></h3>
            </div>
            <div class="col-md-3">
              <h6 class="text-muted">Balance Due</h6>
              <h3 class="mb-0 <%= @invoice.balance_due > 0 ? 'text-danger' : 'text-success' %>">
                $<%= number_with_precision(@invoice.balance_due, precision: 2) %>
              </h3>
            </div>
            <div class="col-md-3">
              <h6 class="text-muted">Payment Status</h6>
              <span class="badge <%= @invoice.paid_in_full? ? 'bg-success' : 'bg-warning' %> fs-6">
                <%= @invoice.payment_status %>
              </span>
            </div>
          </div>
          
          <%# Payment Progress Bar %>
          <% if @invoice.amount > 0 %>
            <div class="mt-4">
              <div class="d-flex justify-content-between mb-1">
                <span>Payment Progress</span>
                <span><%= @invoice.payment_percentage %>%</span>
              </div>
              <div class="progress" style="height: 10px;">
                <div class="progress-bar <%= @invoice.paid_in_full? ? 'bg-success' : 'bg-warning' %>" 
                     role="progressbar" 
                     style="width: <%= @invoice.payment_percentage %>%"
                     aria-valuenow="<%= @invoice.payment_percentage %>" 
                     aria-valuemin="0" 
                     aria-valuemax="100">
                </div>
              </div>
              <div class="text-muted text-center mt-1">
                <%= number_with_precision(@invoice.total_paid, precision: 2) %> / 
                <%= number_with_precision(@invoice.amount, precision: 2) %>
              </div>
            </div>
          <% end %>
        </div>
      </div>
    </div>
  </div>

  <%# Transactions Table %>
  <div class="card">
    <div class="card-header">
      <h5 class="card-title mb-0">
        <i class="bi bi-credit-card me-2"></i>Payment Transactions
        <span class="badge bg-secondary ms-2"><%= @transactions.count %></span>
      </h5>
    </div>
    <div class="card-body">
      <% if @transactions.any? %>
        <div class="table-responsive">
          <table class="table table-hover">
            <thead>
              <tr>
                <th>Date</th>
                <th>Reference #</th>
                <th>Payment Method</th>
                <th class="text-end">Amount</th>
                <th>Recorded By</th>
                <th>Notes</th>
                <th class="text-end">Actions</th>
              </tr>
            </thead>
            <tbody>
              <% @transactions.each do |transaction| %>
                <tr>
                  <td><%= transaction.created_at.strftime('%b %d, %Y') %></td>
                  <td>
                    <code><%= transaction.reference_number %></code>
                    <% if transaction.voided? %>
                      <span class="badge bg-danger ms-1">Voided</span>
                    <% end %>
                  </td>
                  <td>
                    <span class="badge bg-light text-dark">
                      <%= transaction.payment_method.titleize %>
                    </span>
                  </td>
                  <td class="text-end fw-bold">
                    $<%= number_with_precision(transaction.amount, precision: 2) %>
                  </td>
                  <td>
                    <%= transaction.user&.email || 'System' %>
                  </td>
                  <td>
                    <% if transaction.notes.present? %>
                      <small class="text-muted"><%= truncate(transaction.notes, length: 50) %></small>
                    <% else %>
                      <span class="text-muted">No notes</span>
                    <% end %>
                  </td>
                  <td class="text-end">
                    <div class="btn-group btn-group-sm">
                      <%= link_to transaction_path(transaction), class: 'btn btn-outline-primary', title: 'View' do %>
                        <i class="bi bi-eye"></i>
                      <% end %>
                      <%= link_to receipt_transaction_path(transaction), class: 'btn btn-outline-success', title: 'Receipt' do %>
                        <i class="bi bi-receipt"></i>
                      <% end %>
                      <% if current_user.can_pay_invoices? && !transaction.voided? %>
                        <div class="dropdown">
                          <button class="btn btn-outline-secondary dropdown-toggle" type="button" data-bs-toggle="dropdown">
                            <i class="bi bi-gear"></i>
                          </button>
                          <ul class="dropdown-menu">
                            <li>
                              <%= button_to void_transaction_path(transaction), 
                                    method: :post,
                                    class: 'dropdown-item text-danger',
                                    data: { confirm: 'Are you sure you want to void this transaction?' } do %>
                                <i class="bi bi-x-circle me-2"></i>Void Transaction
                              <% end %>
                            </li>
                            <li>
                              <%= link_to refund_transaction_path(transaction), 
                                    class: 'dropdown-item text-warning' do %>
                                <i class="bi bi-arrow-counterclockwise me-2"></i>Refund
                              <% end %>
                            </li>
                          </ul>
                        </div>
                      <% end %>
                    </div>
                  </td>
                </tr>
              <% end %>
            </tbody>
            <tfoot>
              <tr class="table-light">
                <td colspan="3" class="text-end fw-bold">Total Paid:</td>
                <td class="text-end fw-bold text-success">
                  $<%= number_with_precision(@invoice.total_paid, precision: 2) %>
                </td>
                <td colspan="3"></td>
              </tr>
            </tfoot>
          </table>
        </div>
      <% else %>
        <div class="text-center py-5">
          <div class="text-muted">
            <i class="bi bi-credit-card display-4 d-block mb-3"></i>
            <h4>No payments recorded</h4>
            <p class="mb-4">No payment transactions have been recorded for this invoice yet.</p>
            <%= link_to 'Record First Payment', new_transaction_path(invoice_id: @invoice.id), class: 'btn btn-primary' %>
          </div>
        </div>
      <% end %>
    </div>
  </div>

  <%# Quick Actions %>
  <% if current_user.can_pay_invoices? && @invoice.balance_due > 0 %>
    <div class="row mt-4">
      <div class="col-md-12">
        <div class="card border-primary">
          <div class="card-header bg-primary text-white">
            <h5 class="card-title mb-0">
              <i class="bi bi-lightning-charge me-2"></i>Quick Payment Actions
            </h5>
          </div>
          <div class="card-body">
            <div class="row">
              <div class="col-md-4">
                <%= link_to new_transaction_path(invoice_id: @invoice.id, amount: @invoice.balance_due), 
                      class: 'btn btn-success w-100 py-3' do %>
                  <i class="bi bi-check-circle me-2"></i>
                  Pay Full Balance<br>
                  <small>$<%= number_with_precision(@invoice.balance_due, precision: 2) %></small>
                <% end %>
              </div>
              <div class="col-md-4">
                <%= link_to new_transaction_path(invoice_id: @invoice.id), 
                      class: 'btn btn-primary w-100 py-3' do %>
                  <i class="bi bi-credit-card me-2"></i>
                  Custom Payment<br>
                  <small>Enter any amount</small>
                <% end %>
              </div>
              <div class="col-md-4">
                <%= link_to new_pos_transaction_path(invoice_id: @invoice.id), 
                      class: 'btn btn-warning w-100 py-3' do %>
                  <i class="bi bi-cash-coin me-2"></i>
                  POS Payment<br>
                  <small>Point of Sale</small>
                <% end %>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  <% end %>
</div>