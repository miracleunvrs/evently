class AdminController < ApplicationController
  before_action :authenticate!
  before_action :admin!

  def overview
    return if performed?
    render json: { events: Event.count, users: User.count, registrations: Registration.where(status: "confirmed").count, visits: Ticket.where(status: "used").count }
  end
end
