# frozen_string_literal: true

DiscourseModerationApi::Engine.routes.draw do
  get "/examples" => "examples#index"
  # define routes here
end

Discourse::Application.routes.draw { mount ::DiscourseModerationApi::Engine, at: "moderation-api" }
