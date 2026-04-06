# app/controllers/payments_controller.rb
class PaymentsController < ApplicationController
  skip_before_action :verify_authenticity_token, only: [:webhook]
  before_action :authenticate_user!, except: [:webhook]
  
  def new
    @inspection = Inspection.find(params[:inspection_id])
    @amount = @inspection.total_estimated_cost
    @stripe_publishable_key = ENV['STRIPE_PUBLISHABLE_KEY']
  end
  
  def create_payment_intent
    @inspection = Inspection.find(params[:inspection_id])
    
    payment_intent = Stripe::PaymentIntent.create(
      amount: (@inspection.total_estimated_cost * 100).to_i,
      currency: 'ttd',
      metadata: {
        inspection_id: @inspection.id,
        vehicle_plate: @inspection.vehicle.license_plate,
        customer_email: params[:customer_email]
      }
    )
    
    render json: { client_secret: payment_intent.client_secret }
  end
  
  def confirm_payment
    @inspection = Inspection.find(params[:inspection_id])
    
    if params[:payment_intent_id].present?
      payment_intent = Stripe::PaymentIntent.retrieve(params[:payment_intent_id])
      
      if payment_intent.status == 'succeeded'
        @inspection.update!(
          payment_status: 'paid',
          paid_at: Time.current
        )
        
        # Create payment record
        Payment.create!(
          inspection: @inspection,
          amount: payment_intent.amount / 100.0,
          payment_method: 'card',
          status: 'completed',
          transaction_id: payment_intent.id,
          paid_at: Time.current
        )
        
        flash[:notice] = "✅ Payment successful! Your vehicle is ready for pickup."
      else
        flash[:alert] = "Payment not completed. Please try again."
      end
    end
    
    redirect_to customer_dashboard_path
  end
  
  def webhook
    payload = request.body.read
    sig_header = request.env['HTTP_STRIPE_SIGNATURE']
    endpoint_secret = ENV['STRIPE_WEBHOOK_SECRET']
    
    event = Stripe::Webhook.construct_event(payload, sig_header, endpoint_secret)
    
    case event.type
    when 'payment_intent.succeeded'
      payment_intent = event.data.object
      # Handle successful payment
      Rails.logger.info "Payment succeeded: #{payment_intent.id}"
    end
    
    render json: { received: true }
  end
end