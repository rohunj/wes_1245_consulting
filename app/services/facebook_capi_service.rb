require 'net/http'
require 'uri'
require 'json'
require 'digest'

class FacebookCapiService
  PIXEL_ID = ENV['FB_PIXEL_ID']
  ACCESS_TOKEN = ENV['FB_CAPI_TOKEN']
  TEST_EVENT_CODE = ENV['FB_TEST_EVENT_CODE']

  def self.send_event(event_name:, event_id:, user_data:, custom_data: {})
    # Log detailed data to Sentry before sending to Facebook CAPI
    # crumb = Sentry::Breadcrumb.new(
    #   category: 'facebook_capi',
    #   message: "Sending #{event_name} event to Facebook CAPI",
    #   data: {
    #     event_name: event_name,
    #     event_id: event_id,
    #     user_data: user_data,
    #     custom_data: custom_data,
    #     pixel_id: PIXEL_ID,
    #     has_test_event_code: TEST_EVENT_CODE.present?
    #   },
    #   level: 'info'
    # )
    # Sentry.add_breadcrumb(crumb)
    # Sentry.capture_message("#{event_name} #{event_id}")

    uri = URI("https://graph.facebook.com/v18.0/#{PIXEL_ID}/events?access_token=#{ACCESS_TOKEN}")

    event_data = {
      event_name: event_name,
      event_time: Time.now.to_i,
      event_id: event_id,
      user_data: user_data,
      custom_data: custom_data,
      action_source: 'website'
    }

    # Add test_event_code only if environment variable is set and not empty
    event_data[:test_event_code] = TEST_EVENT_CODE if TEST_EVENT_CODE.present?

    payload = {
      data: [event_data]
    }

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    request = Net::HTTP::Post.new(uri.path + '?' + uri.query, { 'Content-Type' => 'application/json' })
    request.body = payload.to_json
    response = http.request(request)
    Rails.logger.info("FB CAPI response: #{response.body}")
    response
  end

  # Hash PII for better match rates
  def self.hash_data(data)
    data.to_s.strip.downcase.then { |v| v.empty? ? nil : Digest::SHA256.hexdigest(v) }
  end
end 