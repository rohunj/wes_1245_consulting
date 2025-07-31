Sentry.init do |config|
  config.dsn = ENV['SENTRY_DSN']
  config.breadcrumbs_logger = [:active_support_logger, :http_logger]
  
  # Set traces_sample_rate to 1.0 to capture 100% of transactions for performance monitoring.
  # We recommend adjusting this value in production.
  config.traces_sample_rate = 1.0
  
  # Enable performance monitoring
  config.enable_tracing = true
  
  # Filter out sensitive data
  config.before_send = lambda do |event, hint|
    # Remove sensitive data from webhook payloads
    if event.request && event.request.data
      event.request.data = event.request.data.gsub(/("password":\s*"[^"]*")/, '"password": "[FILTERED]"')
      event.request.data = event.request.data.gsub(/("email":\s*"[^"]*")/, '"email": "[FILTERED]"')
    end
    event
  end
end 