require 'net/http'
require 'uri'
require 'json'

class CalendlyController < ApplicationController
  CALENDLY_CLIENT_ID = ENV['CALENDLY_CLIENT_ID']
  CALENDLY_CLIENT_SECRET = ENV['CALENDLY_CLIENT_SECRET']
  CALENDLY_REDIRECT_URI = 'https://1245consulting.com/calendly/oauth/callback'
  DEFAULT_ORGANIZATION_URI = 'https://api.calendly.com/organizations/8aafd945-5b43-4691-9856-0e1552ae05e4'

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
        # create_webhook_subscription(token_response['access_token'])
        
        flash[:notice] = "Calendly connected successfully! Webhook subscription created."
      else
        flash[:error] = "Failed to get access token from Calendly."
      end
    else
      flash[:error] = "Authorization failed. No code received from Calendly."
    end
    
    redirect_to root_path
  end

  def list_subscriptions
    access_token = session[:calendly_access_token]
    scope = params[:scope] || 'organization'
    organization = params[:organization] || DEFAULT_ORGANIZATION_URI
    
    if access_token.present?
      begin
        subscriptions = get_webhook_subscriptions(access_token, scope, organization)
        render json: {
          success: true,
          subscriptions: subscriptions,
          scope: scope,
          organization: organization
        }
      rescue => e
        render json: {
          success: false,
          error: e.message
        }, status: :internal_server_error
      end
    else
      render json: {
        success: false,
        error: "No Calendly access token found. Please authorize first."
      }, status: :unauthorized
    end
  end

  def create_manual_subscription
    access_token = session[:calendly_access_token]
    user_uri = params[:user_uri]
    
    if access_token.blank?
      render json: {
        success: false,
        error: "No Calendly access token found. Please authorize first."
      }, status: :unauthorized
      return
    end
    
    # Use default organization URI instead of user_uri
    organization_uri = DEFAULT_ORGANIZATION_URI
    
    begin
      success = create_webhook_subscription_with_uri(access_token, organization_uri)
      
      if success
        render json: {
          success: true,
          message: "Webhook subscription created successfully",
          organization_uri: organization_uri
        }
      else
        render json: {
          success: false,
          error: "Failed to create webhook subscription"
        }, status: :internal_server_error
      end
    rescue => e
      render json: {
        success: false,
        error: e.message
      }, status: :internal_server_error
    end
  end

  def get_access_token
    access_token = session[:calendly_access_token]
    
    if access_token.present?
      render json: {
        success: true,
        has_token: true,
        access_token: access_token,
        token_length: access_token.length
      }
    else
      render json: {
        success: true,
        has_token: false,
        message: "No Calendly access token found in session"
      }
    end
  end

  def delete_subscription
    access_token = session[:calendly_access_token]
    webhook_uuid = params[:webhook_uuid]
    
    if access_token.blank?
      render json: {
        success: false,
        error: "No Calendly access token found. Please authorize first."
      }, status: :unauthorized
      return
    end
    
    if webhook_uuid.blank?
      render json: {
        success: false,
        error: "Webhook UUID is required. Please provide the webhook UUID to delete."
      }, status: :bad_request
      return
    end
    
    begin
      success = delete_webhook_subscription(access_token, webhook_uuid)
      
      if success
        render json: {
          success: true,
          message: "Webhook subscription deleted successfully",
          webhook_uuid: webhook_uuid
        }
      else
        render json: {
          success: false,
          error: "Failed to delete webhook subscription"
        }, status: :internal_server_error
      end
    rescue => e
      render json: {
        success: false,
        error: e.message
      }, status: :internal_server_error
    end
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
    user_uri = get_user_organization_uri(access_token)
    
    Rails.logger.info("User URI: #{user_uri}")
    
    if user_uri.blank?
      Rails.logger.error("Failed to get user URI from Calendly API")
      return false
    end

    uri = URI('https://api.calendly.com/webhook_subscriptions')
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    request = Net::HTTP::Post.new(uri)
    request['Authorization'] = "Bearer #{access_token}"
    request['Content-Type'] = 'application/json'
    
    payload = {
      url: 'https://1245consulting.com/calendly_webhook',
      events: ['invitee.created'],
      organization: DEFAULT_ORGANIZATION_URI,
      scope: 'organization'
    }
    
    Rails.logger.info("Webhook payload: #{payload.to_json}")
    request.body = payload.to_json
    
    response = http.request(request)
    Rails.logger.info("Webhook creation response: #{response.code} - #{response.body}")
    
    if response.code == '201'
      Rails.logger.info("Webhook subscription created successfully")
      return true
    else
      Rails.logger.error("Failed to create webhook subscription: #{response.body}")
      return false
    end
  end

  def create_webhook_subscription_with_uri(access_token, user_uri)
    uri = URI('https://api.calendly.com/webhook_subscriptions')
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    request = Net::HTTP::Post.new(uri)
    request['Authorization'] = "Bearer #{access_token}"
    request['Content-Type'] = 'application/json'
    
    payload = {
      url: 'https://1245consulting.com/calendly_webhook',
      events: ['invitee.created'],
      organization: DEFAULT_ORGANIZATION_URI,
      scope: 'organization'
    }
    
    Rails.logger.info("Webhook payload: #{payload.to_json}")
    request.body = payload.to_json
    
    response = http.request(request)
    Rails.logger.info("Webhook creation response: #{response.code} - #{response.body}")
    
    if response.code == '201'
      Rails.logger.info("Webhook subscription created successfully")
      return true
    else
      Rails.logger.error("Failed to create webhook subscription: #{response.body}")
      return false
    end
  end

  def delete_webhook_subscription(access_token, webhook_uuid)
    uri = URI("https://api.calendly.com/webhook_subscriptions/#{webhook_uuid}")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    request = Net::HTTP::Delete.new(uri)
    request['Authorization'] = "Bearer #{access_token}"
    request['Content-Type'] = 'application/json'
    
    response = http.request(request)
    Rails.logger.info("Webhook deletion response: #{response.code} - #{response.body}")
    
    if response.code == '204'
      Rails.logger.info("Webhook subscription deleted successfully")
      return true
    else
      Rails.logger.error("Failed to delete webhook subscription: #{response.body}")
      return false
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

  def get_webhook_subscriptions(access_token, scope = 'organization', organization = nil)
    uri = URI('https://api.calendly.com/webhook_subscriptions')
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    request = Net::HTTP::Get.new(uri)
    request['Authorization'] = "Bearer #{access_token}"
    request['Content-Type'] = 'application/json'
    
    params = {}
    params['scope'] = scope if scope
    params['organization'] = organization if organization
    
    uri.query = URI.encode_www_form(params) unless params.empty?

    response = http.request(request)
    
    if response.code == '200'
      data = JSON.parse(response.body)
      data['data'] || []
    else
      Rails.logger.error("Failed to get webhook subscriptions: #{response.code} - #{response.body}")
      []
    end
  end
end 