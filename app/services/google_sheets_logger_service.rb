require 'net/http'
require 'uri'
require 'json'
require 'base64'
require 'openssl'

class GoogleSheetsLoggerService
  # Configure your Google Sheets settings here
  SPREADSHEET_ID = ENV['GOOGLE_SHEETS_SPREADSHEET_ID']
  SERVICE_ACCOUNT_JSON_BASE64 = ENV['GOOGLE_SHEETS_SERVICE_ACCOUNT_JSON_BASE64']
  SHEET_NAME = ENV['GOOGLE_SHEETS_SHEET_NAME'] || 'Events' # Default to Sheet1

  def self.log_capi_event(event_name:, event_id:, user_data:, custom_data: {})
    return unless SPREADSHEET_ID.present? && SERVICE_ACCOUNT_JSON_BASE64.present?

    begin
      # Prepare row data
      row_data = [
        Time.current.iso8601,           # Timestamp
        'CAPI_EVENT',                   # Event Type
        event_name,                     # Event Name
        event_id,                       # Event ID
        user_data[:client_ip_address],  # IP Address
        user_data[:client_user_agent],  # User Agent
        user_data[:em],                 # Hashed Email
        user_data[:fn],                 # Hashed First Name
        user_data[:ln],                 # Hashed Last Name
        user_data[:fbc],                # Facebook Click ID
        user_data[:fbp],                # Facebook Browser ID
        custom_data[:utm_source],       # UTM Source
        custom_data[:utm_medium],       # UTM Medium
        custom_data[:utm_campaign],     # UTM Campaign
        custom_data[:utm_term],         # UTM Term
        custom_data[:utm_content],      # UTM Content
        Rails.env,                      # Environment
        '1245_consulting'               # Service Name
      ]

      # Append row to Google Sheet using Google Sheets API v4
      append_to_sheet(row_data)

      Rails.logger.info("CAPI event logged to Google Sheets: #{event_name} - #{event_id}")
    rescue => e
      Rails.logger.error("Google Sheets Logger error: #{e.message}")
    end
  end

  def self.log_webhook_event(service:, payload:, extracted_data: {})
    return unless SPREADSHEET_ID.present? && SERVICE_ACCOUNT_JSON_BASE64.present?

    begin
      # Prepare row data for webhook
      row_data = [
        Time.current.iso8601,           # Timestamp
        'WEBHOOK_EVENT',                # Event Type
        service,                        # Service (Typeform/Calendly)
        extracted_data[:email],         # Email
        extracted_data[:first_name],    # First Name
        extracted_data[:last_name],     # Last Name
        extracted_data[:utm_source],    # UTM Source
        extracted_data[:utm_medium],    # UTM Medium
        extracted_data[:utm_campaign],  # UTM Campaign
        extracted_data[:utm_term],      # UTM Term
        extracted_data[:utm_content],   # UTM Content
        payload.length,                 # Payload Size
        Rails.env,                      # Environment
        '1245_consulting'               # Service Name
      ]

      # Append row to Google Sheet
      append_to_sheet(row_data)

      Rails.logger.info("Webhook event logged to Google Sheets: #{service}")
    rescue => e
      Rails.logger.error("Google Sheets Logger error: #{e.message}")
    end
  end

  private

  def self.append_to_sheet(values)
    # Get access token using service account
    access_token = get_access_token
    
    # Google Sheets API v4 endpoint for appending values
    uri = URI("https://sheets.googleapis.com/v4/spreadsheets/#{SPREADSHEET_ID}/values/#{SHEET_NAME}!A:Z:append?valueInputOption=RAW")
    
    Rails.logger.info("Google Sheets API URL: #{uri}")
    Rails.logger.info("Spreadsheet ID: #{SPREADSHEET_ID}")
    Rails.logger.info("Sheet Name: #{SHEET_NAME}")
    
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.open_timeout = 10
    http.read_timeout = 10

    request = Net::HTTP::Post.new(uri.path + '?' + uri.query, {
      'Content-Type' => 'application/json',
      'Authorization' => "Bearer #{access_token}",
      'User-Agent' => '1245-Consulting-Sheets-Logger/1.0'
    })

    # Prepare the request body
    request_body = {
      values: [values]
    }
    request.body = request_body.to_json

    Rails.logger.info("Request body: #{request_body.to_json}")

    response = http.request(request)

    Rails.logger.info("Response code: #{response.code}")
    Rails.logger.info("Response body: #{response.body}")

    if response.code != '200'
      Rails.logger.error("Google Sheets API error: #{response.code} - #{response.body}")
    end

    response
  end

  def self.get_access_token
    # Decode base64 service account JSON
    service_account_json = Base64.decode64(SERVICE_ACCOUNT_JSON_BASE64)
    service_account = JSON.parse(service_account_json)
    
    # Create JWT claim
    now = Time.now.to_i
    claim = {
      iss: service_account['client_email'],
      scope: 'https://www.googleapis.com/auth/spreadsheets',
      aud: 'https://oauth2.googleapis.com/token',
      exp: now + 3600, # 1 hour
      iat: now
    }

    # Sign the JWT using standard Ruby libraries
    jwt = create_jwt(claim, service_account['private_key'])

    # Exchange JWT for access token
    uri = URI('https://oauth2.googleapis.com/token')
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true

    request = Net::HTTP::Post.new(uri.path, {
      'Content-Type' => 'application/x-www-form-urlencoded'
    })

    request.body = URI.encode_www_form({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion: jwt
    })

    response = http.request(request)
    token_data = JSON.parse(response.body)
    
    token_data['access_token']
  end

  def self.create_jwt(claim, private_key)
    # Create JWT header
    header = {
      alg: 'RS256',
      typ: 'JWT'
    }

    # Encode header and payload
    encoded_header = base64_url_encode(header.to_json)
    encoded_payload = base64_url_encode(claim.to_json)

    # Create the data to sign
    data = "#{encoded_header}.#{encoded_payload}"

    # Sign the data
    private_key_obj = OpenSSL::PKey::RSA.new(private_key)
    signature = private_key_obj.sign(OpenSSL::Digest::SHA256.new, data)
    encoded_signature = base64_url_encode(signature)

    # Return the complete JWT
    "#{encoded_header}.#{encoded_payload}.#{encoded_signature}"
  end

  def self.base64_url_encode(data)
    # Base64 encode and make URL safe
    Base64.strict_encode64(data)
      .tr('+', '-')
      .tr('/', '_')
      .gsub(/=+$/, '')
  end
end 