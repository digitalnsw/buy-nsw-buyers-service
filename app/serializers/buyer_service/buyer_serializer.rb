module BuyerService
  class BuyerSerializer
    include SharedModules::Serializer

    def initialize(buyer:, buyers:)
      @buyers = buyers
      @buyer = buyer
    end

    def attributes(buyer)
      escape_recursive buyer.attributes.slice('id',
                             'state',
                             'started_at',
                             'submitted_at',
                             'name',
                             'organisation',
                             'application_body',
                             'cloud_purchase',
                             'contactable',
                             'contact_number',
                             'employment_status',
                             'manager_name',
                             'manager_email')
    end

    def show
      { buyer: attributes(@buyer) }
    end

    def index
      {
        buyers: @buyers.map do |buyer|
          attributes(buyer)
        end
      }
    end
  end
end
