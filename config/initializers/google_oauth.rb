# Google is one integration provider. Each Google service is unlocked by its own
# scopes, so adding one means adding it here, exposing an accessor on
# Integrations::Google::Client, and adding a label under accounts.show.google.services.
account_scopes = %w[email profile]

service_scopes = {
  calendar: %w[https://www.googleapis.com/auth/calendar]
}

Rails.application.configure do
  config.x.google_oauth.client_id = ENV["GOOGLE_CLIENT_ID"]
  config.x.google_oauth.client_secret = ENV["GOOGLE_CLIENT_SECRET"]
  # Pinned rather than derived from the request, so the value Google receives is
  # always the one registered in the console.
  config.x.google_oauth.redirect_uri = "#{ENV.fetch("APP_URL", "http://localhost:3000").chomp("/")}/auth/google_oauth2/callback"
  config.x.google_oauth.account_scopes = account_scopes
  config.x.google_oauth.service_scopes = service_scopes
  config.x.google_oauth.scopes = account_scopes + service_scopes.values.flatten
end

OmniAuth.config.logger = Rails.logger
OmniAuth.config.failure_raise_out_environments = []

google_oauth = Rails.application.config.x.google_oauth

if google_oauth.client_id.present? && google_oauth.client_secret.present?
  Rails.application.config.middleware.use OmniAuth::Builder do
    provider :google_oauth2,
             google_oauth.client_id,
             google_oauth.client_secret,
             scope: google_oauth.scopes.join(" "),
             redirect_uri: google_oauth.redirect_uri,
             access_type: "offline",
             prompt: "consent",
             skip_jwt: true
  end
end
