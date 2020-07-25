module BuyerService
  class ApplicationController < ActionController::API
    include SharedModules::Authentication
  end
end
