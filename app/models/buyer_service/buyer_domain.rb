require 'securerandom'
module BuyerService
  class BuyerDomain < BuyerService::ApplicationRecord
    self.table_name = 'buyer_domains'
    include PgSearch::Model
    pg_search_scope :search_by_domain, against: [:domain, :organisation]
    acts_as_paranoid column: :discarded_at
  end
end
