# app/jobs/invoice_pdf_job.rb
class InvoicePdfJob < ApplicationJob
  queue_as :default
  
  def perform(invoice_id)
    invoice = Invoice.find(invoice_id)
    
    html = ApplicationController.render(
      template: 'invoices/show',
      layout: 'pdf',
      assigns: { invoice: invoice }
    )
    
    pdf = WickedPdf.new.pdf_from_string(html)
    
    # Attach to invoice or save to file
    # invoice.pdf.attach(io: StringIO.new(pdf), filename: "invoice-#{invoice.invoice_number}.pdf")
    
    Rails.logger.info "📄 PDF generated for invoice #{invoice.invoice_number}"
  end
end