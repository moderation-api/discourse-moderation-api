module DiscourseModerationApi
    class WebhooksController < ::ApplicationController
        skip_before_action :verify_authenticity_token
        before_action :verify_webhook_signature
  
        def receive
            Rails.logger.info("Received webhook: #{request.raw_post}")

            payload = JSON.parse(request.raw_post) rescue {}

            if payload["event"] == "something_happened"
                Rails.logger.info("Handling 'something_happened' event...")
                # Your custom logic here
            end

            render json: { status: payload }, status: 200
        end

        private

        def verify_webhook_signature
            # Skip verification if no signing secret is configured
            return true if SiteSetting.moderation_api_webhook_signing_secret.blank?

            signature = request.headers['modapi-signature'].to_s

            # Require signature if secret is configured
            if signature.blank?
                Rails.logger.warn("Webhook signature missing")
                render json: { 
                    error: "Signature required",
                    time: Time.current
                }, status: 401
                return false
            end

            raw_body = request.raw_post
            expected_signature = OpenSSL::HMAC.hexdigest(
                'sha256',
                SiteSetting.moderation_api_webhook_signing_secret,
                raw_body
            )

            # Convert both signatures to buffers for comparison
            actual_sig = signature.strip
            expected_sig = expected_signature.strip

            # Verify signatures match using secure comparison
            unless actual_sig.bytesize == expected_sig.bytesize &&
                   ActiveSupport::SecurityUtils.secure_compare(actual_sig, expected_sig)
                Rails.logger.warn("Webhook signature verification failed")
                render json: { 
                    error: "Signature verification failed",
                    time: Time.current
                }, status: 401
                return false
            end

            true
        end
    end
end