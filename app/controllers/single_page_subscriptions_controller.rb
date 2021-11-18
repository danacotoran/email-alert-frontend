class SinglePageSubscriptionsController < ApplicationController
  include AccountHelper
  include GovukPersonalisation::ControllerConcern

  UNSUBSCRIBE_FLASH = "email-unsubscribe-success".freeze

  before_action do
    head :not_found unless govuk_account_auth_enabled?
  end

  skip_before_action :verify_authenticity_token, only: [:create]
  before_action :fetch_subscriber_list, only: %i[create]
  before_action :not_found_without_topic_id, only: %i[edit show]

  def show; end

  def create
    unless logged_in?
      redirect_to new_single_page_subscription_path(topic_id: @topic_id) and return
    end

    subscriber = GdsApi.email_alert_api.authenticate_subscriber_by_govuk_account(
      govuk_account_session: @account_session_header,
    ).to_h.fetch("subscriber")

    subscriptions = GdsApi.email_alert_api.get_subscriptions(id: subscriber.fetch("id")).to_h.fetch("subscriptions", [])

    subscription = subscriptions.find { |s| s["subscriber_list"]["id"] == @subscriber_list["id"] }

    if subscription
      GdsApi.email_alert_api.unsubscribe(subscription["id"])
      account_flash_add UNSUBSCRIBE_FLASH
    else
      result = CreateAccountSubscriptionService.call(@subscriber_list, "immediately", @account_session_header)
      account_flash_add CreateAccountSubscriptionService::SUCCESS_FLASH
      set_account_session_header(result[:govuk_account_session])
    end

    redirect_to @content_item.fetch("base_path")
  rescue GdsApi::HTTPUnauthorized
    logout!
    sign_in_and_confirm(@topic_id)
  end

  def edit
    sign_in_and_confirm(topic_id)
  end

private

  def not_found_without_topic_id
    head :not_found and return unless topic_id
  end

  def topic_id
    @topic_id = params[:topic_id]
  end

  def fetch_subscriber_list
    @content_item = GdsApi.content_store.content_item(params.fetch(:base_path)).to_h
    @subscriber_list = GdsApi.email_alert_api.find_or_create_subscriber_list(
      {
        url: @content_item.fetch("base_path"),
        title: @content_item.fetch("title"),
        content_id: @content_item.fetch("content_id"),
      },
    ).to_h.fetch("subscriber_list")
    @topic_id = @subscriber_list.fetch("slug")
  end

  def sign_in_and_confirm(topic_id)
    redirect_with_analytics GdsApi.account_api.get_sign_in_url(
      redirect_path: confirm_account_subscription_path(topic_id: topic_id, return_to_url: true),
    )["auth_uri"]
  end
end
