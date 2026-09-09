Rails.application.routes.draw do
  devise_for :users, controllers: { sessions: "users/sessions" }, skip: %i[registrations passwords]

  namespace :admin do
    root to: "users#index"
    resources :users, only: %i[index show update]
    resources :action_executions, only: %i[index], path: "actions"
  end

  namespace :api do
    namespace :v1 do
      resource :me, only: :show, controller: "me"
      post "auth/signup", to: "auth#signup"
      post "auth/login", to: "auth#login"
      delete "auth/logout", to: "auth#logout"
      post "auth/password", to: "auth#create_password"
      put "auth/password", to: "auth#update_password"

      get "integrations", to: "integrations#index"
      post "integrations/telegram/connect", to: "integrations#connect_telegram"
      delete "integrations/telegram", to: "integrations#disconnect_telegram"
      post "integrations/google/connect", to: "integrations#connect_google"
      delete "integrations/google", to: "integrations#disconnect_google"
      match "integrations/google/connect", to: "integrations#connect_google_preflight", via: :options

      resources :reminders, only: %i[index create show update destroy]
      post "ai/messages", to: "ai_messages#create"
      get "calendar/events", to: "calendar_events#index"
      post "calendar/events", to: "calendar_events#create"
      patch "calendar/events/:id", to: "calendar_events#update", constraints: { id: /[^\/]+/ }
      delete "calendar/events/:id", to: "calendar_events#destroy", constraints: { id: /[^\/]+/ }

      namespace :studywell do
        get "settings", to: "settings#show"
        patch "settings", to: "settings#update"

        get "courses", to: "courses#index"
        post "courses", to: "courses#create"
        get "courses/:id", to: "courses#show"
        patch "courses/:id", to: "courses#update"
        delete "courses/:id", to: "courses#destroy"

        get "courses/:course_id/obligations", to: "obligations#index"
        post "courses/:course_id/obligations", to: "obligations#create"
        get "obligations/:id", to: "obligations#show"
        patch "obligations/:id", to: "obligations#update"
        delete "obligations/:id", to: "obligations#destroy"
      end
    end
  end

  # Account-recovery transport: Core-hosted HTML form for the emailed reset
  # token. Not an admin page and not a Devise member account route.
  get "auth/password/edit", to: "passwords#edit", as: :edit_auth_password
  put "auth/password", to: "passwords#update", as: :auth_password

  # OmniAuth intercepts the request phase, so #new only runs when Google is not configured.
  post "auth/google_oauth2", to: "integrations/google_connections#new", as: :google_oauth_request
  get "auth/google_oauth2/connect", to: "integrations/google_connections#transport", as: :google_oauth_connect
  get "auth/google_oauth2/callback", to: "integrations/google_connections#create"
  get "auth/failure", to: "integrations/google_connections#failure"

  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  root to: redirect("/admin", status: 302)
end
