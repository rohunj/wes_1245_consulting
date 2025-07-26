require 'net/http'
require 'uri'
require 'json'

class CalendlyController < ApplicationController
  CALENDLY_CLIENT_ID = ENV['CALENDLY_CLIENT_ID']
  CALENDLY_CLIENT_SECRET = ENV['CALENDLY_CLIENT_SECRET']
  CALENDLY_REDIRECT_URI = 'https://www.1245consulting.com/calendly/oauth/callback'

  def authorize
    # Generate OAuth authorization URL
    auth_url = "https://auth.calendly.com/oauth/authorize?" + URI.encode_www_form({
      client_id: CALENDLY_CLIENT_ID,
      response_type: 'code',
      redirect_uri: CALENDLY_REDIRECT_URI
    })
    
    redirect_to auth_url, allow_other_host: true

  end

  def callback
    code = params[:code]
    
    if code.present?
      # Exchange authorization code for access token
      token_response = exchange_code_for_token(code)
      
      if token_response['access_token'].present?
        # Store the access token (you might want to save this to your database)
        session[:calendly_access_token] = token_response['access_token']
        
        # Create webhook subscription
        create_webhook_subscription(token_response['access_token'])
        
        flash[:notice] = "Calendly connected successfully! Webhook subscription created."
      else
        flash[:error] = "Failed to get access token from Calendly."
      end
    else
      flash[:error] = "Authorization failed. No code received from Calendly."
    end
    
    redirect_to root_path
  end

  private

  def exchange_code_for_token(code)
    uri = URI('https://auth.calendly.com/oauth/token')
    
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    
    request = Net::HTTP::Post.new(uri)
    request['Content-Type'] = 'application/x-www-form-urlencoded'
    request.body = URI.encode_www_form({
      grant_type: 'authorization_code',
      client_id: CALENDLY_CLIENT_ID,
      client_secret: CALENDLY_CLIENT_SECRET,
      code: code,
      redirect_uri: CALENDLY_REDIRECT_URI
    })
    
    response = http.request(request)
    JSON.parse(response.body)
  end

  def create_webhook_subscription(access_token)
    # First, get the user's organization URI
    user_uri = get_user_organization_uri(access_token)
    
    return unless user_uri
    
    # Create webhook subscription
    uri = URI('https://api.calendly.com/webhook_subscriptions')
    
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    
    request = Net::HTTP::Post.new(uri)
    request['Authorization'] = "Bearer #{access_token}"
    request['Content-Type'] = 'application/json'
    
    payload = {
      url: 'https://1245consulting.com/calendly_webhook',
      events: ['invitee.created'],
      organization: user_uri,
      scope: 'user'
    }
    
    request.body = payload.to_json
    
    response = http.request(request)
    Rails.logger.info("Webhook creation response: #{response.body}")
    
    if response.code == '201'
      Rails.logger.info("Webhook subscription created successfully")
    else
      Rails.logger.error("Failed to create webhook subscription: #{response.body}")
    end
  end

  def get_user_organization_uri(access_token)
    uri = URI('https://api.calendly.com/users/me')
    
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    
    request = Net::HTTP::Get.new(uri)
    request['Authorization'] = "Bearer #{access_token}"
    
    response = http.request(request)
    data = JSON.parse(response.body)
    
    data.dig('resource', 'uri')
  end
end 