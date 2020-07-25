module BuyerService
  class Engine < ::Rails::Engine
    isolate_namespace BuyerService
    config.generators.api_only = true
  end
end
