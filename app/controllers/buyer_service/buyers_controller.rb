require_dependency "buyer_service/application_controller"

module BuyerService
  class BuyersController < BuyerService::ApplicationController
    skip_before_action :verify_authenticity_token, raise: false, only: [
      :approve_buyer,
      :approve,
      :decline,
      :assign,
      :auto_register,
      :deactivate
    ]

    before_action :authenticate_service, only: [
      :approve_buyer,
      :approve,
      :decline,
      :assign,
      :deactivate,
      :auto_register,
      :check_email
    ]

    before_action :authenticate_service_or_user, only: [:my_buyer, :can_buy, :show]
    before_action :authenticate_user, only: [:index, :create, :update]
    before_action :set_buyer, only: [:show, :can_buy]

    def auto_register
      email = params[:email].downcase.strip
      user_id = params[:user_id].to_i
      name = params[:name].strip
      domain = email.partition('@').last
      bd = BuyerDomain.find_by(domain: domain)

      raise SharedModules::MethodNotAllowed if bd.nil?

      @buyer = BuyerService::Buyer.find_or_initialize_by(user_id: user_id)

      @buyer.state = 'approved'
      @buyer.started_at ||= Time.now
      @buyer.submitted_at ||= Time.now
      @buyer.decided_at = Time.now
      @buyer.decision_body = 'Auto approved'
      @buyer.name = name
      @buyer.organisation = bd.organisation

      @buyer.save!(validate: false)

      render json: serializer.show, status: :created, location: @buyer
    end

    def send_manager_email
      @buyer.set_manager_approval_token!
      if @buyer.manager_email
        mailer = ::BuyerApplicationMailer.with(buyer_id: @buyer.id)
        mailer.manager_approval_email.deliver_later
      end
    end

    def create_submit_events
      ::SharedModules::SlackPostJob.perform_later(@buyer.id, :buyer_application_submitted.to_s)
      @buyer.create_event(session_user, "Buyer submitted by #{session_user.email}")
    end

    def update
      @buyer = BuyerService::Buyer.find_by(user_id: session_user.id)
      unless @buyer.created?
        raise SharedModules::AlertError.new("Your buyer application is in #{@buyer.state} status")
      end

      BuyerService::Buyer.transaction do
        @buyer.update_attributes!({
          submitted_at: Time.now,
        }.merge(buyer_params))
        @buyer.submit!
      end

      update_session_user(buyer_status: @buyer.state)
      send_manager_email
      create_submit_events

      render json: serializer.show, status: :created, location: @buyer
    end

    def create
      @buyer = BuyerService::Buyer.find_by(user_id: session_user.id)
      if @buyer
        raise SharedModules::AlertError.new("You buyer application is already initiated")
      end

      BuyerService::Buyer.transaction do
        @buyer = BuyerService::Buyer.create!({
          state: 'created',
          user_id: session_user.id,
          started_at: Time.now,
          submitted_at: Time.now,
        }.merge(buyer_params))
        @buyer.create_event(session_user, "Started application")
        @buyer.submit!
      end

      update_session_user(buyer_id: @buyer.id, buyer_status: @buyer.state)
      send_manager_email
      create_submit_events

      render json: serializer.show, status: :created, location: @buyer
    end

    def serializer
      BuyerService::BuyerSerializer.new(buyer: @buyer, buyers: @buyers)
    end

    def my_buyer
      user = session_user || service_user
      @buyers = BuyerService::Buyer.where(user_id: user.id).to_a
      render json: serializer.index
    end

    def index
      if params[:current]
        @buyer = BuyerService::Buyer.where(user_id: session_user.id).first
        if @buyer
          render json: serializer.show
        else
          render json: {}
        end
      end
    end

    def show
      render json: serializer.show
    end

    def can_buy
      render json: @buyer.approved?
    end

    def approve_buyer
      buyer = BuyerService::Buyer.find_by(manager_approval_token: params[:manager_approval_token])
      if buyer && buyer.may_manager_approve?
        buyer.run_action(:manager_approval, no_user: true)
        render json: { message: "manager approved" }, status: 200
      else
        render json: { errors: ["Buyer not found"] }, status: 404
      end
    end

    def run_operation(operation)
      set_buyer
      @buyer.run_action(operation, user: session_user)
      render json: { success: true }
    end

    def run_admin_operation(operation)
      @buyer = BuyerService::Buyer.where(id: params[:id]).first
      if operation == :assign
        @buyer.run_action(operation, user: service_user, props: {assignee: {id: params[:assignee][:user_id], email: params[:assignee][:user_email]}})
      elsif operation == :deactivate
        @buyer.run_action(operation, user: service_user)
      else
        @buyer.run_action(operation, user: service_user, props: {response: params[:response]})
      end
    end

    def assign
      run_admin_operation(:assign)
      render json: { success: true }
    end

    def approve
      run_admin_operation(:approve)
      ::BuyerApplicationMailer.with(buyer_id: @buyer.id).application_approved_email.deliver_later
      render json: { success: true }
    end

    def decline
      run_admin_operation(:decline)
      ::BuyerApplicationMailer.with(buyer_id: @buyer.id).application_rejected_email.deliver_later
      render json: { success: true }
    end

    def deactivate
      run_admin_operation(:deactivate)
      render json: { success: true }
    end

    def stats
      render json: {
        pending: BuyerService::Buyer.where(state: [:awaiting_manager_approval, :awaiting_assignment, :ready_for_review]).count(:id),
        approved: BuyerService::Buyer.approved.count(:id),
      }
    end

    def check_email
      email = params[:email].downcase.strip
      domain = email.partition('@').last
      render json: {
        valid: URI::MailTo::EMAIL_REGEXP.match?(email) &&
        ( BuyerService::BuyerDomain.exists?(domain: domain) ||
          BuyerService::BuyerEmail.exists?(email: email) )
      }
    end

    private

    def set_buyer
      if service_auth?
        @buyer = BuyerService::Buyer.find(params[:id])
      else
        raise SharedModules::MethodNotAllowed unless session_user.is_buyer?
        @buyer = BuyerService::Buyer.where(user_id: session_user.id).find(params[:id])
      end
    end

    def buyer_params
      params[:buyer].permit(
        :name,
        :organisation,
        :application_body,
        :cloud_purchase,
        :contactable,
        :contact_number,
        :employment_status,
        :manager_name,
        :manager_email,
      ).to_h.symbolize_keys
    end
  end
end
