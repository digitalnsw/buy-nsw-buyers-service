$:.push File.expand_path("../lib", __FILE__)

# Maintain your gem's version:
require "buyer_service/version"

# Describe your gem and declare its dependencies:
Gem::Specification.new do |s|
  s.name        = "buyer_service"
  s.version     = BuyerService::VERSION
  s.authors     = ["Arman"]
  s.email       = ["arman.sarrafi@customerservice.nsw.gov.au"]
  s.homepage    = ""
  s.summary     = "Summary of BuyerService."
  s.description = "Description of BuyerService."
  s.license     = "MIT"

  s.files = Dir["{app,config,db,lib}/**/*", "MIT-LICENSE", "Rakefile", "README.md"]
end
