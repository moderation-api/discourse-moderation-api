module DiscourseModerationApi
    class WebhooksController < ::ApplicationController
        skip_before_action :verify_authenticity_token
        before_action :verify_webhook_signature
  
        def receive
            Rails.logger.info("Received webhook: #{request.raw_post}")

            # Get the system user for moderation actions
            @system_user = DiscourseModerationApi.system_user
            unless @system_user && @system_user.id > 0
                Rails.logger.error("Moderation API bot user not found or has invalid ID: #{@system_user&.id}")
                render json: { error: "System configuration error - bot user not available" }, status: 500
                return
            end

            payload = JSON.parse(request.raw_post) rescue {}

            # Check if the payload has type=QUEUE_ITEM_ACTION
            unless payload["type"] == "QUEUE_ITEM_ACTION"
                Rails.logger.info("Ignoring webhook with type: #{payload["type"]}")
                render json: { status: "ignored", message: "Only QUEUE_ITEM_ACTION type is processed" }, status: 200
                return
            end

            item = payload["item"]
            action = payload["action"]

            content_id = item["id"].to_i
            context_id = item["contextId"].to_i

            if content_id <= 0
                Rails.logger.error("Invalid content ID: #{item["id"]}")
                render json: { error: "Invalid content ID" }, status: 400
                return
            end

            # Find the content based on content_type
            post = nil
            reviewables = []
            
            post = Post.unscoped.find_by(id: content_id)
            reviewables = Reviewable.where(target: post) if post

            unless post || reviewables.any?
                Rails.logger.error("Could not find post, topic, or reviewable with id: #{content_id}")
                render json: { error: "Content not found for id: #{content_id}" }, status: 404
                return
            end

            case action["key"]
            when "discourse:delete"
                if post
                    PostDestroyer.new(@system_user, post).destroy
                end
                # Process reviewables in all cases
                reviewables.each do |reviewable|
                    reviewable.destroy
                end
            when "discourse:hide"
                if post
                    # Hide the post with the moderator action reason
                    post.hide!(
                        PostActionType.types[:moderator_action],
                        Post.hidden_reasons[:moderator_action],
                        custom_message: action["value"]
                    )
                    # if post is the first post in the topic, show the topic
                    if post.post_number == 1
                        # get the topic
                        post.topic.update!(visible: false)
                    end
                end
                # Process reviewables in all cases
                reviewables.each do |reviewable|
                    reviewable.destroy
                end
            when "discourse:show"
                if post
                    Rails.logger.debug("LOG:ModerationAPI: showing post: #{post.id}")
                    post.update!(hidden: false)
                    # if post is the first post in the topic, show the topic
                    if post.post_number == 1
                        # get the topic
                        post.topic.update!(visible: true)
                    end
                end
                # Process reviewables in all cases
                reviewables.each do |reviewable|
                    reviewable.destroy
                end
            else
                Rails.logger.warn("Unknown action key: #{action["key"]}")
                render json: { error: "Unknown action" }, status: 400
                return
            end

            render json: { 
                status: "success",
                action: action["key"],
                content_type: content_type,
                content_id: content_id,
                topic_id: context_id
            }, status: 200
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