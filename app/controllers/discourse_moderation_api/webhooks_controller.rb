module DiscourseModerationApi
    class WebhooksController < ::ApplicationController
        skip_before_action :verify_authenticity_token # ✅ Allows external POST requests
  
        def receive
            Rails.logger.info("Received webhook: #{request.raw_post}")

            payload = JSON.parse(request.raw_post) rescue {}

            if payload["event"] == "something_happened"
                Rails.logger.info("Handling 'something_happened' event...")
                # Your custom logic here
            end

            render json: { status: "ok" }, status: 200
        end
    end
end
  