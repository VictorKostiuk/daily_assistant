Rails.application.configure do
  config.x.open_router.api_key = ENV["OPEN_ROUTER_KEY"]
  config.x.open_router.model = ENV.fetch("OPEN_ROUTER_MODEL", "google/gemma-4-26b-a4b-it:free")
  config.x.open_router.app_url = ENV.fetch("APP_URL", "http://localhost:3000").chomp("/")
  config.x.open_router.app_name = "Daily Assistant"
end
