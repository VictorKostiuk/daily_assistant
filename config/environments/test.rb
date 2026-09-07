# The test environment is used exclusively to run your application's
# test suite. You never need to work with it otherwise. Remember that
# your test database is "scratch space" for the test suite and is wiped
# and recreated between test runs. Don't rely on the data there!

Rails.application.configure do
  # Settings specified here will take precedence over those in config/application.rb.

  # While tests run files are not watched, reloading is not necessary.
  config.enable_reloading = false

  # Eager loading loads your entire application. When running a single test locally,
  # this is usually not necessary, and can slow down your test suite. However, it's
  # recommended that you enable it in continuous integration systems to ensure eager
  # loading is working properly before deploying your code.
  config.eager_load = ENV["CI"].present?

  # Configure public file server for tests with cache-control for performance.
  config.public_file_server.headers = { "cache-control" => "public, max-age=3600" }

  # Show full error reports.
  config.consider_all_requests_local = true
  # :null_store discards everything written to Rails.cache, which silently breaks
  # PendingAction (used by every multi-stage Telegram conversation flow).
  config.cache_store = :memory_store

  # Render exception templates for rescuable exceptions and raise for other exceptions.
  config.action_dispatch.show_exceptions = :rescuable

  # Disable request forgery protection in test environment.
  config.action_controller.allow_forgery_protection = false

  # Store uploaded files on the local file system in a temporary directory.
  config.active_storage.service = :test

  config.active_job.queue_adapter = :test

  config.action_mailer.delivery_method = :test
  config.action_mailer.default_url_options = { host: "www.example.com" }

  # Print deprecation notices to the stderr.
  config.active_support.deprecation = :stderr

  # Raises error for missing translations.
  # config.i18n.raise_on_missing_translations = true

  # Annotate rendered view with file names.
  # config.action_view.annotate_rendered_view_with_filenames = true

  # Raise error when a before_action's only/except options reference missing actions.
  config.action_controller.raise_on_missing_callback_actions = true

  # Synthetic values so a bare `bundle exec rspec` boots without real secrets.
  ENV["TELEGRAM_BOT_TOKEN"] ||= "test-telegram-bot-token"
  ENV["OPEN_ROUTER_KEY"] ||= "test-open-router-key"
  # Mount OmniAuth's Google strategy so POST /auth/google_oauth2 is the real
  # request phase. Without these, google_oauth.rb skips the middleware and the
  # route falls through to #new — the attack matrix would never reach Google.
  ENV["GOOGLE_CLIENT_ID"] ||= "test-google-client-id"
  ENV["GOOGLE_CLIENT_SECRET"] ||= "test-google-client-secret"
  config.active_record.encryption.primary_key = "testPrimaryKeyNotForProduction1"
  config.active_record.encryption.deterministic_key = "testDeterministicKeyNotForProd01"
  config.active_record.encryption.key_derivation_salt = "testKeyDerivationSaltNotForPrd01"
end
