class PagesController < ApplicationController
  before_action :authenticate_user!, only: [:logout]

  def home
  end
  def thankyou
  end
  def free_estimate
    Rails.logger.info("Free Estimate Visited")
    FacebookCapiService.send_event(
      event_name: 'FreeEstimateVisited',
      event_id: SecureRandom.uuid,
      user_data: {
        client_ip_address: request.remote_ip,
        client_user_agent: request.user_agent
      },
      custom_data: utm_params
    )
  end
  def logout
    sign_out(current_user)
    redirect_to root_path
  end

  def page
    @page_key = request.path[1..-1]
    render "pages/#{@page_key}"
  end

  def calendly
    Rails.logger.info("Calendly Visited")
    FacebookCapiService.send_event(
      event_name: 'CalendlyVisited',
      event_id: SecureRandom.uuid,
      user_data: {
        client_ip_address: request.remote_ip,
        client_user_agent: request.user_agent
      },
      custom_data: utm_params
    )
  end

  skip_before_action :verify_authenticity_token, only: [:track_calendly, :typeform_webhook, :calendly_webhook]
  def track_calendly
    utms = params[:utms] || {}
    FacebookCapiService.send_event(
      event_name: 'CalendlyScheduled',
      event_id: SecureRandom.uuid,
      user_data: {
        client_ip_address: request.remote_ip,
        client_user_agent: request.user_agent
      },
      custom_data: utms
    )
    head :ok
  end

  def typeform_webhook
    payload = request.body.read
    Rails.logger.info("TypeForm Webhook Payload: #{payload}")
    data = JSON.parse(payload) rescue {}

    answers = data.dig('form_response', 'answers') || []
    hidden = data.dig('form_response', 'hidden') || {}

    email = answers.find { |a| a['type'] == 'email' }&.dig('email')
    hashed_email = FacebookCapiService.hash_data(email)

    user_data = {
      client_ip_address: request.remote_ip,
      client_user_agent: request.user_agent,
      em: hashed_email
    }.compact

    custom_data = {
      utm_source: hidden['utm_source'],
      utm_medium: hidden['utm_medium'],
      utm_campaign: hidden['utm_campaign'],
      utm_term: hidden['utm_term'],
      utm_content: hidden['utm_content']
    }.compact

    FacebookCapiService.send_event(
      event_name: 'FreeEstimateSubmitted',
      event_id: SecureRandom.uuid,
      user_data: user_data,
      custom_data: custom_data
    )

    head :ok
    # Return the parsed payload for demo testing
    # render json: {
    #   received_payload: data,
    #   extracted_data: {
    #     answers: answers,
    #     hidden: hidden,
    #     email: email,
    #     hashed_email: hashed_email,
    #     user_data: user_data,
    #     custom_data: custom_data
    #   }
    # }
  end

  def calendly_webhook
    payload = request.body.read
    Rails.logger.info("Calendly Webhook Payload: #{payload}")
    data = JSON.parse(payload) rescue {}

    event_type = data['event']
    invitee = data['payload'] && data['payload']['invitee']

    email = invitee && invitee['email']
    name = invitee && invitee['name']
    hashed_email = FacebookCapiService.hash_data(email)

    user_data = {
      client_ip_address: request.remote_ip,
      client_user_agent: request.user_agent,
      em: hashed_email
    }.compact

    # Extract UTM params from tracking object (directly under payload)
    tracking = data['payload'] && data['payload']['tracking'] || {}
    custom_data = {
      utm_source: tracking['utm_source'],
      utm_medium: tracking['utm_medium'],
      utm_campaign: tracking['utm_campaign'],
      utm_term: tracking['utm_term'],
      utm_content: tracking['utm_content']
    }.compact

    FacebookCapiService.send_event(
      event_name: 'CalendlyScheduled',
      event_id: SecureRandom.uuid,
      user_data: user_data,
      custom_data: custom_data
    )
    Rails.logger.info("Calendly CAPI sent")

    head :ok
    # Return the parsed payload for demo testing
    # render json: {
    #   received_payload: data,
    #   extracted_data: {
    #     event_type: event_type,
    #     email: email,
    #     name: name,
    #     hashed_email: hashed_email,
    #     user_data: user_data,
    #     custom_data: custom_data
    #   }
    # }
  end

  private
  def utm_params
    params.permit(:utm_source, :utm_medium, :utm_campaign, :utm_term, :utm_content)
  end
end
