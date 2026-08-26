# frozen_string_literal: true

Rails.application.routes.draw do
  devise_for :users, skip: :all
  get 'api-docs', to: redirect('/api-docs/index.html')
  get 'openapi/openapi.yaml', to: 'openapi#show'

  namespace :api do
    namespace :v1 do
      namespace :auth do
        post :login, to: 'sessions#create'
        post :refresh, to: 'sessions#refresh'
        delete :logout, to: 'sessions#destroy'
      end

      namespace :candidate do
        namespace :auth do
          namespace :otp do
            post :request, to: 'requests#create'
            post :verify, to: 'verifications#create'
          end
        end

        resources :documents, only: %i[index create]
        resource :profile, only: :show
      end

      namespace :admin do
        resources :candidate_imports, only: :create
      end

      resources :users, only: %i[index create update]
      resource :user_invitation, only: :update

      namespace :users do
        resource :profile, only: :show
      end

      get 'health/live', to: 'health#live'
      get 'health/ready', to: 'health#ready'
    end
  end

  get 'up' => 'rails/health#show', as: :rails_health_check
end
