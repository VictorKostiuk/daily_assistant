require "rails_helper"

RSpec.describe "Admin::ActionExecutions", type: :request do
  it "lets a signed-in admin view the actions list" do
    admin = create(:user, :admin)
    sign_in admin

    get admin_action_executions_path

    expect(response).to have_http_status(:ok)
  end
end
