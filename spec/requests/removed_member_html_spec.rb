require "rails_helper"

RSpec.describe "Removed member HTML surface", type: :request do
  [
    [ :get, "/account" ],
    [ :get, "/actions" ],
    [ :delete, "/integrations/google_connection" ],
    [ :post, "/integrations/telegram_connection" ],
    [ :delete, "/integrations/telegram_connection" ],
    [ :get, "/users/sign_up" ],
    [ :post, "/users" ],
    [ :get, "/users/edit" ],
    [ :put, "/users" ],
    [ :patch, "/users" ],
    [ :delete, "/users" ],
    [ :get, "/users/cancel" ],
    [ :get, "/users/password/new" ],
    [ :get, "/users/password/edit" ],
    [ :post, "/users/password" ],
    [ :put, "/users/password" ],
    [ :patch, "/users/password" ]
  ].each do |verb, path|
    it "#{verb.upcase} #{path} returns 404" do
      public_send(verb, path)

      expect(response).to have_http_status(:not_found)
    end
  end

  it "redirects GET / to /admin with 302" do
    get "/"

    expect(response).to have_http_status(:found)
    expect(response).to redirect_to("/admin")
  end
end
