# frozen_string_literal: true

module ::DiscourseModerationApi
  class ModerationService
    def self.analyze_post(post)
      Rails.logger.debug("Analyzing post content")

      analyze_content(
        content: post.raw,
        author_id: post.user_id.to_s,
        context_id: post.topic_id.to_s,
        content_id: post.id&.to_s || "pending_#{Time.now.to_i}",
        content_url: "#{Discourse.base_url}/t/#{post.topic_id}/#{post.id}",
      )
    end

    def self.analyze_topic(topic)
      Rails.logger.debug("Analyzing topic content")

      content = [topic.title, topic.first_post&.raw].compact.join("\n")

      analyze_content(
        content: content,
        author_id: topic.user_id.to_s,
        context_id: topic.id.to_s,
        content_id: topic.first_post&.id&.to_s || "pending_topic_#{Time.now.to_i}",
        content_url: "#{Discourse.base_url}/t/#{topic.id}",
      )
    end

    private

    def self.analyze_content(content:, author_id:, context_id:, content_id:, content_url:)
      Rails.logger.info("Analyzing content with Moderation API")

      begin
        ModerationApi.configure do |config|
          Rails.logger.debug(
            "Setting up ModerationApi with key: #{SiteSetting.moderation_api_key[0..5]}...",
          )
          config.access_token = SiteSetting.moderation_api_key
        end

        api = ModerationApi::ModerateApi.new

        Rails.logger.debug("Content to analyze: #{content.truncate(100)}")
        Rails.logger.debug(
          "Author ID: #{author_id}, Context ID: #{context_id}, Content ID: #{content_id}",
        )

        params = { value: {
          type: "object",
          data: {
            post: {
              type: "text",
              value: content,
            },
            },
          },
          doNotStore: false,
          metadata: { link: content_url },
        }

        # Add image URLs if present
        if content.present?
          # Extract image URLs from post content using Discourse's built-in cooked parsing
          doc = Nokogiri::HTML5.fragment(PrettyText.cook(content))
          image_urls = doc.css('img').map { |img| img['src'] }.compact
          
          image_urls.each_with_index do |url, index|
            full_url = url.start_with?('http') ? url : "#{Discourse.base_url}#{url}"
            params[:value][:data]["image-#{index + 1}"] = {
              type: "image", 
              value: full_url
            }
          end
        end

        # Only add optional fields if they have values
        params[:authorId] = author_id if author_id.present?
        params[:contextId] = context_id if context_id.present?
        params[:contentId] = content_id if content_id.present?

        Rails.logger.debug("API Params: #{params.inspect}")

        analysis = api.moderation_object(params)

        Rails.logger.debug("API Response: #{analysis.inspect}")

        return { approved: !analysis.flagged }
      rescue ModerationApi::ApiError => e
        Rails.logger.error("Moderation API error: #{e.message}")
        Rails.logger.error("Response body: #{e.response_body}") if e.respond_to?(:response_body)
        Rails.logger.error("Full error: #{e.full_message}")
        Rails.logger.error(e.backtrace.join("\n"))
        # Return approved by default in case of API errors
        return { approved: true }
      rescue StandardError => e
        Rails.logger.error("Unexpected error in moderation service: #{e.message}")
        Rails.logger.error(e.backtrace.join("\n"))
        return { approved: true }
      end
    end
  end
end
