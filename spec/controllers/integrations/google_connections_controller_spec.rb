require "rails_helper"

RSpec.describe Integrations::GoogleConnectionsController, type: :controller do
  render_views

  describe "POST #new" do
    it "returns 503 through the result view with no session and no token side effect" do
      user = create(:user)
      raw = ConnectionToken.issue!(user: user, purpose: ConnectionToken::GOOGLE)

      expect {
        post :new, params: { token: raw }
      }.not_to change {
        [
          ConnectionToken.count,
          ConnectionToken.find_by!(token_digest: ConnectionToken.digest(raw)).used_at,
          user.user_integrations.count
        ]
      }

      expect(response).to have_http_status(:service_unavailable)
      expect(response.body).to include("Google is not configured for this environment yet.")
      expect(session[:google_connect]).to be_blank
      expect(controller.current_user).to be_nil
    end
  end
end
