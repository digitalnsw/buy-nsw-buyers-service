require 'securerandom'
module BuyerService
  class Buyer < BuyerService::ApplicationRecord
    self.table_name = 'buyer_applications'
    include AASM
    extend Enumerize

    include Concerns::StateScopes

    acts_as_paranoid column: :discarded_at

    has_many :product_orders, foreign_key: :buyer_id

    enumerize :cloud_purchase, in: ['make-purchase', 'plan-purchase', 'no-plan']
    enumerize :contactable, in: ['phone-number', 'email', 'none']
    enumerize :employment_status, in: ['employee', 'contractor', 'other-eligible']

    aasm column: :state do
      state :created, initial: true
      state :awaiting_manager_approval
      state :awaiting_assignment
      state :ready_for_review
      state :approved
      state :rejected
      state :deactivated

      event :submit do
        transitions from: :created, to: :awaiting_manager_approval, guard: :requires_manager_approval?

        transitions from: :created, to: :awaiting_assignment,
                    guard: :unassigned?
        transitions from: :created, to: :ready_for_review,
                    guard: :assignee_present?
      end

      event :manager_approve do
        transitions from: :awaiting_manager_approval, to: :awaiting_assignment,
                    guard: :unassigned?
        transitions from: :awaiting_manager_approval, to: :ready_for_review,
                    guard: :assignee_present?
        transitions from: :awaiting_manager_approval, to: :approved
      end

      event :assign do
        transitions from: :awaiting_assignment, to: :ready_for_review
      end

      event :approve do
        transitions from: :ready_for_review, to: :approved
      end

      event :reject do
        transitions from: :ready_for_review, to: :rejected
      end

      event :deactivate do
        transitions from: :approved, to: :deactivated
      end
    end

    def requires_manager_approval?
      employment_status == 'contractor'
    end

    def assignee_present?
      assigned_to_id.present?
    end

    def unassigned?
      !assignee_present?
    end

    def self.find_by_user_and_buyer(user_id, buyer_id)
      where(user_id: user_id, id: buyer_id).first!
    end

    def set_manager_approval_token!
      update_attribute(:manager_approval_token, SecureRandom.hex(16))
    end

    def in_progress?
      created?
    end

    scope :assigned_to, ->(user_id) { where('assigned_to_id = ?', user_id) }
    scope :for_review, -> { awaiting_assignment.or(ready_for_review) }

    def events
      SharedResources::RemoteEvent.get_events(id, 'BuyerApplication')
    end

    def valid_actions
      case state.to_sym
      when :created
        [:submit]
      when :awaiting_manager_approval
        [:manager_approval]
      when :awaiting_assignment
        [:assign]
      when :ready_for_review
        [:approve, :decline]
      when :approved
        [:deactivate]
      when :rejected
        []
      when :deactivated
        [:submit, :cancel, :deactivate]
      end
    end

    def create_event(user, note)
      SharedResources::RemoteEvent.generate_token(user)
      SharedResources::RemoteEvent.create_event(id, 'BuyerApplication', user.id, 'Event::Buyer', note)
    end

    def run_action(action, user: nil, props: {}, no_user: false) # assignee: nil, statuses: nil, response: nil
      raise SharedModules::AlertError.new("Invalid action #{action} in state #{state}, please refresh the page.") unless action.in? valid_actions
      unless no_user
        raise SharedModules::AlertError.new("Unauthorized access #{action} with user #{user.email}.") unless user.is_admin? ||
                                       user.is_buyer? && user_id == user.id
      end
      BuyerService::Buyer.transaction do
        note = send(action, user, props)
        create_event(user, note) if user
      end
    end

    def manager_approval(user, props)
      self.update_attributes!(manager_approved_at: Time.now, manager_approval_token: nil)
      self.manager_approve!
      "Manager #{manager_name} (#{manager_email}) approved the buyer"
    end

    def decide(user, props)
      update_attributes!(decided_at: Time.now, decision_body: props[:response])
    end

    def assign(user, props)
      update_attributes!(assigned_to_id: props[:assignee][:id])
      self.assign!
      "Buyer submission assigned by #{user.email} to #{props[:assignee][:email]}."
    end

    def approve(user, props)
      decide(user, props)
      self.approve!
      "Buyer approved by #{user.email}. Response was: #{props[:response]}."
    end

    def decline(user, props)
      decide(user, props)
      self.reject!
      "Buyer declined by #{user.email}. Response was: #{props[:response]}."
    end

    def deactivate(user, props)
      self.deactivate!
      "Buyer deactivated by #{user.email}."
    end
  end
end
