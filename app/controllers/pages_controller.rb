class PagesController < ApplicationController
  before_action :authenticate_user!, only: [:logout]

  def home
    # CAPI event now handled by AJAX call from frontend
  end
  def thankyou
  end
  def free_estimate
    # CAPI event now handled by AJAX call from frontend
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
    # CAPI event now handled by AJAX call from frontend
  end

  skip_before_action :verify_authenticity_token, only: [:typeform_webhook, :calendly_webhook, :capi_free_estimate_visited, :capi_calendly_visited, :capi_homepage_visited]
  def typeform_webhook
    payload = request.body.read
    # Rails.logger.info("TypeForm Webhook Payload: #{payload}")
    data = JSON.parse(payload) rescue {}

    answers = data.dig('form_response', 'answers') || []
    hidden = data.dig('form_response', 'hidden') || {}

    # Extract email, first name, and last name from answers using field IDs
    email = answers.find { |a| a['field']['id'] == 'vOcR9ilRM3VK' }&.dig('email')
    first_name = answers.find { |a| a['field']['id'] == 'PEHVSljYxZTn' }&.dig('text')
    last_name = answers.find { |a| a['field']['id'] == 'CitDWWwiuJga' }&.dig('text')

    # Hash PII data for CAPI
    hashed_email = FacebookCapiService.hash_data(email)
    hashed_first_name = FacebookCapiService.hash_data(first_name)
    hashed_last_name = FacebookCapiService.hash_data(last_name)

    user_data = {
      client_ip_address: request.remote_ip,
      client_user_agent: request.user_agent,
      em: hashed_email,
      fn: hashed_first_name,
      ln: hashed_last_name
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

    # Log webhook to Google Sheets
    GoogleSheetsLoggerService.log_webhook_event(
      service: 'Typeform',
      payload: payload,
      extracted_data: {
        email: email,
        first_name: first_name,
        last_name: last_name,
        utm_source: hidden['utm_source'],
        utm_medium: hidden['utm_medium'],
        utm_campaign: hidden['utm_campaign'],
        utm_term: hidden['utm_term'],
        utm_content: hidden['utm_content']
      }
    )

    head :ok
    # Return the parsed payload for demo testing
    # render json: {
    #   received_payload: data,
    #   extracted_data: {
    #     answers: answers,
    #     hidden: hidden,
    #     email: email,
    #     first_name: first_name,
    #     last_name: last_name,
    #     hashed_email: hashed_email,
    #     hashed_first_name: hashed_first_name,
    #     hashed_last_name: hashed_last_name,
    #     user_data: user_data,
    #     custom_data: custom_data
    #   }
    # }
  end

  def calendly_webhook
    payload = request.body.read
    # Rails.logger.info("Calendly Webhook Payload: #{payload}")
    data = JSON.parse(payload) rescue {}

    event_type = data['event']
    invitee = data['payload'] && data['payload']['invitee']

    email = invitee && invitee['email']
    first_name = invitee && invitee['first_name']
    last_name = invitee && invitee['last_name']
    hashed_email = FacebookCapiService.hash_data(email)
    hashed_first_name = FacebookCapiService.hash_data(first_name)
    hashed_last_name = FacebookCapiService.hash_data(last_name)

    user_data = {
      client_ip_address: request.remote_ip,
      client_user_agent: request.user_agent,
      em: hashed_email,
      fn: hashed_first_name,
      ln: hashed_last_name
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
    # Rails.logger.info("Calendly CAPI sent")

    # Log webhook to Google Sheets
    GoogleSheetsLoggerService.log_webhook_event(
      service: 'Calendly',
      payload: payload,
      extracted_data: {
        email: email,
        first_name: first_name,
        last_name: last_name,
        utm_source: tracking['utm_source'],
        utm_medium: tracking['utm_medium'],
        utm_campaign: tracking['utm_campaign'],
        utm_term: tracking['utm_term'],
        utm_content: tracking['utm_content']
      }
    )

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

  def capi_free_estimate_visited
    utms = params[:utms] || {}
    fbc = params[:fbc]
    fbp = params[:fbp]
    event_id = params[:event_id]
    
    user_data = {
      client_ip_address: request.remote_ip,
      client_user_agent: request.user_agent
    }
    
    # Add fbc and fbp to user_data if present
    user_data[:fbc] = fbc if fbc.present?
    user_data[:fbp] = fbp if fbp.present?
    
    FacebookCapiService.send_event(
      event_name: 'FreeEstimateVisited',
      event_id: event_id || SecureRandom.uuid,
      user_data: user_data,
      custom_data: utms
    )
    
    head :ok
  end
  
  def capi_calendly_visited
    utms = params[:utms] || {}
    fbc = params[:fbc]
    fbp = params[:fbp]
    event_id = params[:event_id]
    
    user_data = {
      client_ip_address: request.remote_ip,
      client_user_agent: request.user_agent
    }
    
    # Add fbc and fbp to user_data if present
    user_data[:fbc] = fbc if fbc.present?
    user_data[:fbp] = fbp if fbp.present?
    
    FacebookCapiService.send_event(
      event_name: 'CalendlyVisited',
      event_id: event_id || SecureRandom.uuid,
      user_data: user_data,
      custom_data: utms
    )
    
    head :ok
  end

  def capi_homepage_visited
    utms = params[:utms] || {}
    fbc = params[:fbc]
    fbp = params[:fbp]
    event_id = params[:event_id]
    
    user_data = {
      client_ip_address: request.remote_ip,
      client_user_agent: request.user_agent
    }
    
    # Add fbc and fbp to user_data if present
    user_data[:fbc] = fbc if fbc.present?
    user_data[:fbp] = fbp if fbp.present?
    
    FacebookCapiService.send_event(
      event_name: 'PageView',
      event_id: event_id || SecureRandom.uuid,
      user_data: user_data,
      custom_data: utms
    )
    
    head :ok
  end

  private
  def utm_params
    params.permit(:utm_source, :utm_medium, :utm_campaign, :utm_term, :utm_content)
  end
end
