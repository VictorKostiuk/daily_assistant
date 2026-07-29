Rails.application.routes.draw do
  devise_for :users
  resource :account, only: :show

  namespace :integrations do
    resource :google_connection, only: :destroy
    resource :telegram_connection, only: %i[create destroy]
  end

  # OmniAuth intercepts the request phase, so #new only runs when Google is not configured.
  post "auth/google_oauth2", to: "integrations/google_connections#new", as: :google_oauth_request
  get "auth/google_oauth2/callback", to: "integrations/google_connections#create"
  get "auth/failure", to: "integrations/google_connections#failure"

  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Defines the root path route ("/")
  # root "posts#index"
  root "pages#home"
end
