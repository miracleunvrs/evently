Rails.application.routes.draw do
  get "/health", to: "health#show"
  get "/health/solana", to: "health#solana"

  scope "/auth" do
    post "/register", to: "auth#register"
    post "/login", to: "auth#login"
    post "/refresh", to: "auth#refresh"
    get "/me", to: "auth#me"
  end

  scope "/wallet" do
    post "/challenge", to: "wallets#challenge"
    post "/verify", to: "wallets#verify"
  end

  resources :events, only: %i[index show create update] do
    member do
      post :register
      post :waitlist
      get :guests
      get :stats
    end
  end
  delete "/registrations/:id", to: "events#cancel_registration"

  get "/me/tickets", to: "tickets#index"
  get "/me/waitlist", to: "events#my_waitlist"
  get "/me/favorites", to: "favorites#index"
  post "/me/favorites", to: "favorites#create"
  delete "/me/favorites/:event_id", to: "favorites#destroy"

  get "/tickets/:id", to: "tickets#show"
  post "/tickets/:id/blockchain", to: "tickets#confirm_blockchain"
  get "/tickets/:id/blockchain_status", to: "tickets#blockchain_status"
  post "/check-in/prepare", to: "check_ins#prepare"
  post "/check-in", to: "check_ins#create"

  get "/categories", to: "categories#index"
  get "/admin/overview", to: "admin#overview"
end
