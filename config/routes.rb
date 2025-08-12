Rails.application.routes.draw do
  root 'pages#home'

  devise_for :users
  get 'logout', to: 'pages#logout', as: 'logout'

  resources :subscribe, only: [:index]
  resources :dashboard, only: [:index]
  resources :account, only: [:index, :update]
  resources :billing_portal, only: [:create]
  match '/billing_portal' => 'billing_portal#create', via: [:get]
  match '/cancel' => 'billing_portal#destroy', via: [:get]
  post 'capi/free_estimate_visited', to: 'pages#capi_free_estimate_visited'
  post 'capi/calendly_visited', to: 'pages#capi_calendly_visited'
  post 'capi/homepage_visited', to: 'pages#capi_homepage_visited'
  post 'capi/calendly_scheduled', to: 'pages#capi_calendly_scheduled'
  post 'typeform_webhook', to: 'pages#typeform_webhook'
  post 'calendly_webhook', to: 'pages#calendly_webhook'
  
  # (development only)
  if Rails.env.development?
    # Calendly OAuth routes
    get 'calendly/oauth/authorize', to: 'calendly#authorize'
    get 'calendly/oauth/callback', to: 'calendly#callback'
    # Calendly Webhook Management routes 
    get 'calendly/subscriptions', to: 'calendly#list_subscriptions'
    get 'calendly/create_subscription', to: 'calendly#create_manual_subscription'
    get 'calendly/access_token', to: 'calendly#get_access_token'
    get 'calendly/delete_subscription', to: 'calendly#delete_subscription'
  end

  # static pages
  pages = %w(
    privacy terms thankyou free_estimate calendly
  )

  pages.each do |page|
    get "/#{page}", to: "pages##{page}", as: "#{page.gsub('-', '_')}"
  end

  # admin panels
  authenticated :user, -> user { user.admin? } do
    namespace :admin do
      resources :dashboard, only: [:index]
      resources :impersonations, only: [:new]
      resources :users, only: [:edit, :update, :destroy]
    end

    # convenience helper
    get 'admin', to: 'admin/dashboard#index'
  end
end
