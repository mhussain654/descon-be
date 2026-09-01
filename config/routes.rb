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

        resource :bank_detail, path: 'bank_details', only: %i[show update], controller: :bank_details
        resources :documents, only: %i[index create]
        resources :document_submissions, only: :create
        resource :payment, only: %i[show create], controller: :payments
        resource :application_progress, only: :show, controller: :application_progress
        resource :profile, only: :show
        resource :workflow_state, only: :show
        resource :workflow_history, only: :show
        resource :flight_detail, only: :show, controller: :flight_details do
          resource :ticket_access, only: :create, controller: :flight_detail_ticket_accesses
        end
      end

      namespace :admin do
        resources :candidates, only: %i[index create show update] do
          resource :bank_detail, path: 'bank_details', only: :show, controller: :candidate_bank_details do
            resource :proof_access,
                     only: :create,
                     controller: :candidate_bank_detail_proof_accesses
          end
        end
        resources :countries, only: %i[index create update], param: :code do
          post :retirement, on: :member
        end
        resources :projects, only: %i[index create update], param: :code do
          post :retirement, on: :member
        end
        resources :crafts, only: %i[index create update], param: :code do
          post :retirement, on: :member
        end
        resources :candidate_imports, only: :create do
          get :template, on: :collection, controller: :candidate_import_templates, action: :show
        end
        resources :document_submissions, only: %i[index show]
        resources :candidates, only: [] do
          resource :workflow_state, only: :show, controller: :candidate_workflow_states
          resource :workflow_history, only: :show, controller: :candidate_workflow_histories
          resources :workflow_transitions, only: %i[index create], controller: :candidate_workflow_transitions
          resources :qvc_attempts, only: %i[index create update], controller: :candidate_qvc_attempts
          resources :visa_decisions, only: %i[index create], controller: :candidate_visa_decisions do
            resource :visa_copy_access, only: :create, controller: :candidate_visa_decision_visa_copy_accesses
          end
          resource :flight_detail, only: %i[show create update], controller: :candidate_flight_details do
            resource :ticket_access, only: :create, controller: :candidate_flight_detail_ticket_accesses
          end
        end
        resources :candidate_documents, only: [] do
          resource :access, only: :create, controller: :document_accesses
          resources :rejections, only: :create, controller: :document_rejections
          resources :verifications, only: :create, controller: :document_verifications
        end
      end

      resources :users, only: %i[index create update]
      resource :user_invitation, only: :update

      namespace :users do
        resource :profile, only: :show
      end

      namespace :payments do
        scope 'hosted_checkout/:provider_code' do
          get :return, to: 'hosted_checkout_returns#show'
          post :callback, to: 'hosted_checkout_callbacks#create'
        end
      end

      get 'health/live', to: 'health#live'
      get 'health/ready', to: 'health#ready'
    end
  end

  get 'up' => 'rails/health#show', as: :rails_health_check
end
