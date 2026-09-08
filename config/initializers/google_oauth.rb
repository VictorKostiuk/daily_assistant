# Google is one integration provider. Each Google service is unlocked by its own
# scopes, so adding one means adding it here and exposing an accessor on
# Integrations::Google::Client.
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

# Request-phase-only guard. setup_phase also runs on the callback, before
# omniauth.params is restored (omniauth/strategy.rb:268-276), and a real
# callback query is Google's code/state — there is no token in it. Scope the
# query-token check to POST so genuine callbacks are not rejected. The
# callback re-checks intent + token (from env["omniauth.params"]) + active
# user independently. Abort messages stay generic: fail! puts message_key
# into the failure URL.
#
# Production preconditions (not enforced here; a mismatch fails in
# production while every test still passes):
# - the initiating origin is same-site with Core (session cookie is SameSite=Lax)
# - APP_URL, which pins the callback URI, is the same host that set the session cookie
google_connect_setup = lambda do |env|
  next unless env["REQUEST_METHOD"] == "POST"

  token = Rack::Utils.parse_query(env["QUERY_STRING"].to_s)["token"]
  unless Integrations::Google::ConnectIntent.valid?(session: env["rack.session"], token: token)
    raise Integrations::Google::ConnectAborted
  end
end

if google_oauth.client_id.present? && google_oauth.client_secret.present?
  Rails.application.config.middleware.use OmniAuth::Builder do
    provider :google_oauth2,
             google_oauth.client_id,
             google_oauth.client_secret,
             scope: google_oauth.scopes.join(" "),
             redirect_uri: google_oauth.redirect_uri,
             access_type: "offline",
             prompt: "consent",
             skip_jwt: true,
             # The transport Referer is /connect?token=…; the default origin_param
             # would copy that into the failure URL as origin=, whose key is not
             # filtered, so the handoff would log in cleartext.
             origin_param: false,
             setup: google_connect_setup
  end
end
