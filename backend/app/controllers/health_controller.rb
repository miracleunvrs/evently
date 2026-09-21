class HealthController < ApplicationController
  def show
    ActiveRecord::Base.connection.select_value("SELECT 1")
    render json: { ok: true, database: "ok", solana: "configured", network: "devnet" }
  rescue ActiveRecord::ActiveRecordError => error
    render json: { ok: false, database: "down", detail: error.message }, status: :service_unavailable
  end

  def solana
    Solana::Client.new.rpc("getHealth")
    render json: { ok: true, solana: "ok", network: "devnet" }
  rescue Solana::RpcError => error
    render json: { ok: false, solana: "down", detail: error.message }, status: :service_unavailable
  end
end
