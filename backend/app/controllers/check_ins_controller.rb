class CheckInsController < ApplicationController
  before_action :authenticate!

  def prepare
    return unless current_user
    ticket, event = authorized_ticket
    return if performed?
    return render json: { detail: "already used" }, status: :conflict if ticket.status == "used"
    return render json: { detail: "blockchain ticket is not confirmed" }, status: :unprocessable_entity unless ticket.blockchain_status == "confirmed"
    return render json: { detail: "connect and verify organizer Phantom wallet first" }, status: :unprocessable_entity unless current_user.wallet_address.present? && current_user.wallet_verified_at.present?

    render json: { ticket_id: ticket.id, event_id: event.id, memo: check_in_memo(ticket) }
  end

  def create
    return unless current_user
    ticket, event = authorized_ticket
    return if performed?
    signature = params.require(:check_in_signature).to_s
    return render json: { detail: "invalid check-in signature" }, status: :unprocessable_entity unless signature.match?(/\A[1-9A-HJ-NP-Za-km-z]{64,128}\z/)
    return render json: { detail: "connect and verify organizer Phantom wallet first" }, status: :unprocessable_entity unless current_user.wallet_address.present? && current_user.wallet_verified_at.present?

    result = nil
    Ticket.transaction do
      locked = Ticket.lock.find(ticket.id)
      if locked.status == "used"
        result = "duplicate"
      else
        raise Solana::RpcError, "blockchain ticket is not confirmed" unless locked.blockchain_status == "confirmed"
        Solana::TicketVerifier.new(locked).verify!(signature: locked.solana_signature, token_address: locked.token_address)
        Solana::CheckInVerifier.new(current_user).verify!(signature: signature, memo: check_in_memo(locked))
        locked.update!(status: "used", blockchain_status: "used", check_in_signature: signature, checked_in_at: Time.current)
        result = "ok"
      end
      CheckIn.create!(ticket: locked, event: event, checked_by: current_user, result: result)
    end

    return render json: { detail: "already used" }, status: :conflict if result == "duplicate"
    render json: {
      result: "ok",
      event_id: event.id,
      event_title: event.title,
      blockchain_verified: true,
      check_in_signature: signature,
      explorer_url: "https://explorer.solana.com/tx/#{signature}?cluster=devnet"
    }
  rescue Solana::RpcError => error
    render json: { detail: error.message }, status: :service_unavailable
  end

  private

  def authorized_ticket
    ticket = Ticket.includes(registration: :event).find_by!(code: params.require(:code).to_s.strip.upcase)
    event = ticket.registration.event
    unless current_user.role == "admin" || event.organizer_id == current_user.id
      render json: { detail: "not your event" }, status: :forbidden
    end
    [ ticket, event ]
  end

  def check_in_memo(ticket)
    "evently:checkin:v1:#{ticket.id}:#{ticket.registration_id}"
  end
end
