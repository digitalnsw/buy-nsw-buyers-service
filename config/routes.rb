BuyerService::Engine.routes.draw do
  resources :buyers, only: [:create, :update, :show, :index] do
    get :can_buy, on: :member
    get :my_buyer, on: :collection
    post :submit, on: :member
    post :assign, on: :member
    post :approve, on: :member
    post :decline, on: :member
    post :deactivate, on: :member
    post :approve_buyer, on: :collection
    get :stats, on: :collection
    get :check_email, on: :collection
    post :auto_register, on: :collection
  end

  # resources :public_sellers, only: [:index, :show] do
  #   get :count, on: :collection
  # end
end
