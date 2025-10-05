# frozen_string_literal: true

module Decidim
  module VolunteerScheduler
    # Controller for handling external webhook integrations (Scicent token sales)
    class WebhooksController < ApplicationController
      protect_from_forgery with: :null_session
      skip_before_action :verify_authenticity_token
      
      before_action :verify_webhook_signature, only: [:scicent_sale]

      # Endpoint for Scicent token sale webhooks
      # POST /volunteer_scheduler/webhooks/scicent_sale
      def scicent_sale
        Rails.logger.info "Received Scicent sale webhook: #{webhook_params.inspect}"
        
        # Validate required parameters
        unless valid_sale_data?
          render json: { error: 'Invalid sale data' }, status: :bad_request
          return
        end
        
        # Process commission distribution in background
        CommissionDistributionJob.perform_later(sale_data)
        
        Rails.logger.info "Queued commission distribution for transaction: #{sale_data[:transaction_id]}"
        
        render json: { status: 'success', message: 'Commission distribution queued' }, status: :ok
      rescue StandardError => e
        Rails.logger.error "Webhook processing failed: #{e.message}"
        Rails.logger.error e.backtrace.join("\n")
        
        render json: { error: 'Internal server error' }, status: :internal_server_error
      end

      # Health check endpoint for webhook monitoring
      # GET /volunteer_scheduler/webhooks/health
      def health
        render json: { 
          status: 'healthy', 
          timestamp: Time.current.iso8601,
          version: Decidim::VolunteerScheduler::VERSION
        }
      end

      private

      def webhook_params
        params.permit(:user_id, :amount, :transaction_id, :currency, :timestamp, :signature)
      end

      def sale_data
        @sale_data ||= {
          user_id: webhook_params[:user_id].to_i,
          amount: webhook_params[:amount].to_f,
          transaction_id: webhook_params[:transaction_id],
          currency: webhook_params[:currency] || 'SCICENT',
          timestamp: webhook_params[:timestamp]
        }
      end

      def valid_sale_data?
        sale_data[:user_id] > 0 &&
          sale_data[:amount] > 0 &&
          sale_data[:transaction_id].present? &&
          user_exists?
      end

      def user_exists?
        Decidim::User.exists?(id: sale_data[:user_id])
      end

      def verify_webhook_signature
        return if Rails.env.development? # Skip verification in development

        provided_signature = request.headers['X-Scicent-Signature']
        webhook_secret = ENV['SCICENT_WEBHOOK_SECRET']

        unless provided_signature && webhook_secret
          Rails.logger.error "Missing webhook signature or secret"
          render json: { error: 'Unauthorized' }, status: :unauthorized
          return
        end

        payload = request.raw_post
        expected_signature = generate_signature(payload, webhook_secret)

        unless secure_compare(provided_signature, expected_signature)
          Rails.logger.error "Invalid webhook signature"
          render json: { error: 'Unauthorized' }, status: :unauthorized
        end
      end

      def generate_signature(payload, secret)
        'sha256=' + OpenSSL::HMAC.hexdigest(OpenSSL::Digest.new('sha256'), secret, payload)
      end

      def secure_compare(a, b)
        return false unless a.bytesize == b.bytesize

        l = a.unpack("C*")
        r = b.unpack("C*")
        result = 0
        
        l.zip(r) do |x, y|
          result |= x ^ y
        end
        
        result == 0
      end
    end
  end
end