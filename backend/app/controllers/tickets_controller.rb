class TicketsController < ApplicationController
  before_action :authenticate!

  def self.serialize(ticket)
    registration = ticket.registration
    event = registration.event
    {
      id: ticket.id,
      code: ticket.code,
      status: ticket.status,
      event_id: event.id,
      event_title: event.title,
      event: event.as_json(only: %i[id organizer_id title description city place starts_at capacity price status cover_url]).merge(category: event.category&.title, occupied: event.occupied),
      registration_id: registration.id,
      wallet_address: ticket.wallet_address,
      solana_signature: ticket.solana_signature,
      token_address: ticket.token_address,
      blockchain_status: ticket.blockchain_status,
      explorer_url: ticket.explorer_url,
      checked_in_at: ticket.checked_in_at
    }
  end

  def index
    return unless current_user
    tickets = current_user.tickets.includes(registration: :event)
    render json: tickets.map { |ticket| self.class.serialize(ticket) }
  end

  def show
    return unless current_user
    ticket = accessible_ticket
    render json: self.class.serialize(ticket)
  end

  def confirm_blockchain
    return unless current_user
    ticket = current_user.tickets.includes(registration: :event).find(params[:id])
    signature = params.require(:solana_signature).to_s
    token_address = params.require(:token_address).to_s
    return render json: { detail: "invalid signature or token address" }, status: :unprocessable_entity unless signature.match?(/\A[1-9A-HJ-NP-Za-km-z]{64,128}\z/) && token_address.match?(/\A[1-9A-HJ-NP-Za-km-z]{32,44}\z/)

    ticket.with_lock do
      return render json: { detail: "ticket already used" }, status: :conflict if ticket.status == "used"
      return render json: self.class.serialize(ticket) if ticket.blockchain_status == "confirmed" && ticket.solana_signature == signature && ticket.token_address == token_address
      return render json: { detail: "ticket already confirmed" }, status: :conflict if ticket.blockchain_status == "confirmed"

      begin
        Solana::TicketVerifier.new(ticket).verify!(signature: signature, token_address: token_address)
        ticket.update!(solana_signature: signature, token_address: token_address, blockchain_status: "confirmed", blockchain_error: nil)
        render json: self.class.serialize(ticket)
      rescue Solana::RpcError => error
        ticket.update!(blockchain_status: "failed", blockchain_error: error.message)
        render json: { detail: error.message, blockchain_status: "failed" }, status: :unprocessable_entity
      end
    end
  end

  def blockchain_status
    return unless current_user
    ticket = accessible_ticket
    verified = false
    if ticket.solana_signature.present? && ticket.token_address.present?
      verified = Solana::TicketVerifier.new(ticket).verify!(signature: ticket.solana_signature, token_address: ticket.token_address)
    end
    render json: { blockchain_status: ticket.blockchain_status, verified: verified, explorer_url: ticket.explorer_url }
  rescue Solana::RpcError => error
    render json: { blockchain_status: ticket.blockchain_status, verified: false, detail: error.message }, status: :service_unavailable
  end

  private

  def accessible_ticket
    ticket = Ticket.includes(registration: :event).find(params[:id])
    event = ticket.registration.event
    allowed = ticket.registration.user_id == current_user.id || current_user.role == "admin" || event.organizer_id == current_user.id
    raise ActiveRecord::RecordNotFound unless allowed
    ticket
  end
end
