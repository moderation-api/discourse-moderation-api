import Controller from "@ember/controller";
import { action } from "@ember/object";
import { inject as controllerInject } from "@ember/controller";
import { service } from "@ember/service";

export default class AdminPluginsModerationApiController extends Controller {
  @service siteSettings;

  @controllerInject("adminSiteSettings") adminSiteSettings;

  flaggingBehaviors = [
    { name: "Queue for review", value: "Queue for review" },
    { name: "Flag post", value: "Flag post" },
    { name: "Block post", value: "Block post" },
    { name: "Nothing", value: "Nothing" },
  ];

  @action
  updateFlaggingBehavior(value) {
    this.siteSettings.set("moderation_api_flagging_behavior", value);
  }

  @action
  updateBlockMessage(value) {
    this.siteSettings.set("moderation_api_block_message", value);
  }

  @action
  updateNotifyOnPostQueue(value) {
    this.siteSettings.set("moderation_api_notify_on_post_queue", value);
  }

  @action
  updateCheckPrivateMessage(value) {
    this.siteSettings.set("moderation_api_check_private_message", value);
  }

  @action
  updateSkipGroups(value) {
    this.siteSettings.set("moderation_api_skip_groups", value);
  }

  @action
  updateSkipCategories(value) {
    this.siteSettings.set("moderation_api_skip_categories", value);
  }

  @action
  updateApiKey(value) {
    this.siteSettings.set("moderation_api_key", value);
  }

  @action
  updateWebhookSigningSecret(value) {
    this.siteSettings.set("moderation_api_webhook_signing_secret", value);
  }

  @action
  saveSettings() {
    this.adminSiteSettings.saveSettings();
  }
} 