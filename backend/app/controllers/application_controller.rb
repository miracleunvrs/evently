class ApplicationController < ActionController::API
  rescue_from ActiveRecord::RecordNotFound, with: -> { render json: { detail: "not found" }, status: :not_found }
  rescue_from ActiveRecord::RecordInvalid, with: ->(error) { render json: { detail: error.record.errors.full_messages.join(", ") }, status: :unprocessable_entity }
  rescue_from ActiveRecord::RecordNotUnique, with: -> { render json: { detail: "already exists" }, status: :conflict }

  private

  def current_user
    return @current_user if defined?(@current_user)

    header = request.authorization.to_s
    raise JWT::DecodeError, "missing token" unless header.start_with?("Bearer ")
    payload = Auth::Token.decode(header.delete_prefix("Bearer "))
    @current_user = User.find(payload.fetch("sub"))
  rescue JWT::DecodeError, JWT::ExpiredSignature, ActiveRecord::RecordNotFound
    render json: { detail: "invalid or expired token" }, status: :unauthorized
    nil
  end

  def authenticate!
    current_user
  end

  def organizer!
    return if current_user&.role.in?(%w[organizer admin])
    render json: { detail: "organizer required" }, status: :forbidden unless performed?
  end

  def admin!
    return if current_user&.role == "admin"
    render json: { detail: "admin required" }, status: :forbidden unless performed?
  end
end
