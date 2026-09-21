class EventsController < ApplicationController
  before_action :authenticate!, except: %i[index show]
  before_action :organizer!, only: :create

  def index
    relation = Event.includes(:category).where(status: "published").order(id: :desc).limit(100)
    q = params[:q].to_s.strip
    relation = relation.where("events.title ILIKE :q OR events.city ILIKE :q OR events.place ILIKE :q", q: "%#{Event.sanitize_sql_like(q)}%") if q.present?
    relation = relation.where("events.city ILIKE ?", "%#{Event.sanitize_sql_like(params[:city].to_s)}%") if params[:city].present?
    relation = relation.joins(:category).where(categories: { title: params[:category] }) if params[:category].present?
    render json: relation.map { |event| event_json(event) }
  end

  def show
    render json: event_json(Event.where(status: "published").find(params[:id]))
  end

  def create
    return if performed?
    event = current_user.events.create!(event_params)
    render json: event_json(event), status: :created
  end

  def update
    return unless current_user
    event = Event.find(params[:id])
    return render json: { detail: "not your event" }, status: :forbidden unless current_user.role == "admin" || event.organizer_id == current_user.id
    event.update!(event_params)
    render json: event_json(event)
  end

  def register
    return unless current_user
    wallet = current_user.wallet_address
    return render json: { detail: "connect and verify Phantom wallet first" }, status: :unprocessable_entity unless wallet.present? && current_user.wallet_verified_at.present?

    ticket = nil
    Event.transaction do
      event = Event.lock.find(params[:id])
      raise ActiveRecord::RecordNotFound unless event.status == "published"
      existing = event.registrations.find_by(user: current_user)
      if existing
        ticket = existing.ticket
        raise ActiveRecord::RecordNotUnique unless ticket&.blockchain_status.in?(%w[pending failed])
      else
        return render json: { detail: "sold out" }, status: :conflict if event.occupied >= event.capacity
        registration = event.registrations.create!(user: current_user, status: "confirmed")
        ticket = registration.create_ticket!(code: ticket_code(event.id), wallet_address: wallet, blockchain_status: "pending")
      end
      ticket.update!(wallet_address: wallet, blockchain_status: "pending", blockchain_error: nil)
    end
    render json: ticket_json(ticket), status: :created
  end

  def waitlist
    return unless current_user
    registration = nil
    Event.transaction do
      event = Event.lock.find(params[:id])
      return render json: { detail: "seats available" }, status: :conflict if event.occupied < event.capacity
      registration = event.registrations.create!(user: current_user, status: "waitlisted")
    end
    position = Registration.where(event_id: registration.event_id, status: "waitlisted").where("id <= ?", registration.id).count
    render json: waitlist_json(registration, position), status: :created
  end

  def cancel_registration
    return unless current_user
    registration = Registration.find(params[:id])
    return render json: { detail: "registration not found" }, status: :not_found unless registration.user_id == current_user.id || current_user.role == "admin"
    return render json: { detail: "ticket already used" }, status: :conflict if registration.ticket&.status == "used"

    Registration.transaction do
      event = Event.lock.find(registration.event_id)
      released = registration.status == "confirmed"
      registration.destroy!
      next_registration = event.registrations.where(status: "waitlisted").order(:created_at, :id).lock.first if released
      if next_registration
        next_registration.update!(status: "confirmed")
        next_registration.create_ticket!(code: ticket_code(event.id), wallet_address: next_registration.user.wallet_address, blockchain_status: "pending")
      end
    end
    head :no_content
  end

  def my_waitlist
    return unless current_user
    rows = current_user.registrations.includes(:event).where(status: "waitlisted").order(:created_at, :id)
    render json: rows.map { |registration| waitlist_json(registration, Registration.where(event_id: registration.event_id, status: "waitlisted").where("id <= ?", registration.id).count) }
  end

  def guests
    return unless current_user
    event = Event.find(params[:id])
    return render json: { detail: "event not found" }, status: :not_found unless current_user.role == "admin" || event.organizer_id == current_user.id
    render json: event.registrations.includes(:user).map { |registration| { name: registration.user.name, email: registration.user.email, status: registration.status, registered_at: registration.created_at } }
  end

  def stats
    return unless current_user
    event = Event.find(params[:id])
    return render json: { detail: "event not found" }, status: :not_found unless current_user.role == "admin" || event.organizer_id == current_user.id
    render json: { registrations: event.occupied, visits: event.tickets.where(status: "used").count, capacity: event.capacity }
  end

  private

  def event_params
    params.permit(:title, :description, :city, :place, :starts_at, :category_id, :capacity, :price, :cover_url, :status)
  end

  def event_json(event)
    event.as_json(only: %i[id organizer_id title description city place starts_at capacity price status cover_url]).merge(category: event.category&.title, occupied: event.occupied)
  end

  def ticket_json(ticket)
    TicketsController.serialize(ticket)
  end

  def waitlist_json(registration, position)
    { registration_id: registration.id, event_id: registration.event_id, event_title: registration.event.title, status: "waitlisted", position: position }
  end

  def ticket_code(event_id)
    "EVT-#{event_id}-#{SecureRandom.alphanumeric(8).upcase.tr("01IO", "2345")}"
  end
end
