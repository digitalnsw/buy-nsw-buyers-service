Rails.application.routes.draw do
  mount BuyerService::Engine => "/buyer_service"
end
