require 'net/http'
require 'uri'
require 'json'

class HttpLoggerService
  # Configure your logging endpoint here
  LOG_ENDPOINT = ENV['LOG_ENDPOINT'] || 'https://webhook.site/b42f5320-1db8-4dd7-b47f-6f03cfb561ba'
  
  def self.log(level:, message:, data: {})
    return unless LOG_ENDPOINT.present?
    
    log_entry = {
      timestamp: Time.current.iso8601,
      level: level,
      message: message,
      data: data,
      environment: Rails.env,
      service: '1245_consulting'
    }
    
    begin
      uri = URI(LOG_ENDPOINT)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == 'https'
      http.open_timeout = 5
      http.read_timeout = 5
      
      request = Net::HTTP::Post.new(uri.path, {
        'Content-Type' => 'application/json',
        'User-Agent' => '1245-Consulting-Logger/1.0'
      })
      request.body = log_entry.to_json
      
      response = http.request(request)
      
      # Log locally if HTTP logging fails
      if response.code != '200'
        Rails.logger.warn("HTTP Logger failed: #{response.code} - #{response.body}")
      end
    rescue => e
      Rails.logger.warn("HTTP Logger error: #{e.message}")
    end
  end
  
  def self.info(message, data = {})
    log(level: 'info', message: message, data: data)
  end
  
  def self.warn(message, data = {})
    log(level: 'warn', message: message, data: data)
  end
  
  def self.error(message, data = {})
    log(level: 'error', message: message, data: data)
  end
  
  def self.facebook_capi_event(event_name:, event_id:, user_data:, custom_data: {})
    info("Facebook CAPI Event", {
      event_name: event_name,
      event_id: event_id,
      user_data: user_data,
      custom_data: custom_data,
      pixel_id: FacebookCapiService::PIXEL_ID,
      has_test_event_code: FacebookCapiService::TEST_EVENT_CODE.present?
    })
  end
  
  def self.webhook_received(service:, payload:, extracted_data: {})
    info("#{service} Webhook Received", {
      service: service,
      payload_size: payload.length,
      payload: payload,
      extracted_data: extracted_data
    })
  end
end 