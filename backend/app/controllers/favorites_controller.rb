class FavoritesController < ApplicationController
  before_action :authenticate!

  def index
    render json: current_user.favorites.pluck(:event_id) if current_user
  end

  def create
    return unless current_user
    Event.where(status: "published").find(params.require(:event_id))
    current_user.favorites.find_or_create_by!(event_id: params[:event_id])
    render json: { ok: true }, status: :created
  end

  def destroy
    return unless current_user
    current_user.favorites.where(event_id: params[:event_id]).delete_all
    head :no_content
  end
end
