require 'securerandom'
module BuyerService
  class BuyerEmail < BuyerService::ApplicationRecord
    self.table_name = 'buyer_emails'
    include PgSearch::Model
    pg_search_scope :search_by_email, against: [:email, :organisation]
    acts_as_paranoid column: :discarded_at
  end
end
