# frozen_string_literal: true

# name: discourse-moderation-api
# about: Automatically moderates posts using Moderation API
# meta_topic_id: TODO
# version: 0.0.1
# authors: Moderation API
# url: https://moderationapi.com
# required_version: 2.7.0

gem "faraday", "2.12.2", { require: false }
gem "faraday-net_http", "3.4.0", { require: false }
gem "multipart-post", "2.4.1", { require: false }
gem "faraday-multipart", "1.1.0", { require: false }
gem "marcel", "1.0.4", { require: false }
gem "net-http", "0.6.0", { require: false }
gem "moderation_api", "1.2.2", { require: false }

enabled_site_setting :moderation_api_enabled

require "moderation_api"

module ::DiscourseModerationApi
  PLUGIN_NAME = "discourse-moderation-api"

  def self.system_user
    @system_user ||= User.find_by(username: "moderation_api_bot") || create_system_user
  end

  def self.create_system_user
    user =
      User
        .create!(
          username: "moderation_api_bot",
          name: "Moderation API Bot",
          email: "no-reply-discourse@moderationapi.com",
          password: SecureRandom.hex,
          active: true,
          trust_level: TrustLevel[4],
          admin: false,
          approved: true,
          created_at: Time.zone.now,
          last_seen_at: Time.zone.now,
        )
        .tap do |created_user|
          created_user.activate
          created_user.email_tokens.update_all(confirmed: true)
          created_user.user_option.update!(
            email_messages_level: UserOption.email_level_types[:never],
          )

          # Add avatar
          avatar_url = "https://moderationapi.com/logo-round.png"
          if avatar_url
            created_user.create_user_avatar unless created_user.user_avatar
            avatar = UserAvatar.import_url_for_user(avatar_url, created_user)
          end
        end
  end

  def self.should_moderate?(post)
    Rails.logger.debug("ModerationAPI: Checking if post #{post&.id} should be moderated")

    if post.blank? || !SiteSetting.moderation_api_enabled
      Rails.logger.debug("ModerationAPI: Skipping - post is blank or moderation not enabled")
      return false
    end

    # Skip if post already has errors
    if post.errors.present?
      Rails.logger.debug("ModerationAPI: Skipping - post has errors: #{post.errors.full_messages}")
      return false
    end

    # system message bot message or no user
    if (post&.user_id).to_i <= 0
      Rails.logger.debug("ModerationAPI: Skipping - system message or no user")
      return false
    end
    
    # don't check trashed topics
    if !post.topic || post.topic.trashed?
      Rails.logger.debug("ModerationAPI: Skipping - topic is trashed or missing")
      return false
    end

    # Skip if user is in excluded groups
    if SiteSetting.moderation_api_skip_groups.present? &&
         post
           .user
           &.groups
           &.pluck(:id)
           &.intersection(SiteSetting.moderation_api_skip_groups.split("|").map(&:to_i))
           &.any?
      Rails.logger.debug("ModerationAPI: Skipping - user is in excluded groups")
      return false
    end

    # Skip private messages unless enabled
    if (post.topic&.private_message? || post.archetype == "private_message") &&
         !SiteSetting.moderation_api_check_private_message
      Rails.logger.debug("ModerationAPI: Skipping - private message and checking disabled")
      return false
    end

    if Reviewable.exists?(target: post)
      Rails.logger.debug("ModerationAPI: Skipping - reviewable already exists for post")
      return false
    end

    Rails.logger.debug("ModerationAPI: Post #{post.id} will be moderated")
    return true
  end

  def self.handle_moderation_result(post, analysis)
    return if analysis[:approved]

    case SiteSetting.moderation_api_flagging_behavior
    when "Block post"
      post.errors.add(:base, SiteSetting.moderation_api_block_message)
      return false
    when "Queue for review"
      queue_post_for_review(post)
      return false
    when "Flag post"
      PostActionCreator.create(
        system_user,
        post,
        :inappropriate,
        message: "Flagged by Moderation API",
      )
      return false
    when "Nothing"
      return nil
    end
  end

  def self.queue_post_for_review(post)
    # If it's the first post in a topic, hide it instead of destroying
    if post.is_first_post?
      PostDestroyer.new(system_user, post).destroy
    else
      # If it's a reply, destroy the post so no one sees it until a moderator checks
      PostDestroyer.new(system_user, post).destroy
    end

    if SiteSetting.moderation_api_notify_on_post_queue
      SystemMessage.new(post.user).create(
        "moderation_api_post_queued_for_review",
        topic_title: post.topic.title,
        post_link: post.full_url,
      )
    end

    reviewable =
      ReviewableQueuedPost.needs_review!(
        target: post,
        target_created_by: post.user,
        created_by: system_user,
        payload: {
          raw: post.raw,
        },
        reviewable_by_moderator: true,
        potential_spam: true,
      )
  end
end

require_relative "lib/discourse_moderation_api/engine"
require_relative "lib/discourse_moderation_api/moderation_service"

after_initialize do
  pre_create_behaviours = ["Block post"]

  post_create_behaviours = ["Queue for review", "Flag post"]

  # Check before creation only if we're in blocking mode
  on(:before_create_post) do |post, params|
    if DiscourseModerationApi.should_moderate?(post) &&
         pre_create_behaviours.include?(SiteSetting.moderation_api_flagging_behavior)
      analysis = DiscourseModerationApi::ModerationService.analyze_post(post)
      DiscourseModerationApi.handle_moderation_result(post, analysis)
    end
  end

  # For non-blocking moderation, analyze after the post is created
  on(:post_created) do |post|
    if DiscourseModerationApi.should_moderate?(post) &&
         post_create_behaviours.include?(SiteSetting.moderation_api_flagging_behavior)
      analysis = DiscourseModerationApi::ModerationService.analyze_post(post)
      DiscourseModerationApi.handle_moderation_result(post, analysis)
    end
  end

  # For edits, always analyze after save since we'll have the ID
  on(:post_edited) do |post|
    if DiscourseModerationApi.should_moderate?(post)
      analysis = DiscourseModerationApi::ModerationService.analyze_post(post)
      DiscourseModerationApi.handle_moderation_result(post, analysis)
    end
  end

   # Add webhook handler
  Discourse::Application.routes.append do
    post "/moderation-api/webhook" => "discourse_moderation_api/webhooks#receive"
  end

  # add_admin_route "moderation_api.configure_project.title", "moderation-api-config"

  # Discourse::Application.routes.append do
  #   get "/admin/plugins/moderation-api-config" => "admin/plugins#index",
  #       :constraints => StaffConstraint.new
  # end
  
end


