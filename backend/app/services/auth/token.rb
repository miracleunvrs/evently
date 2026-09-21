module Auth
  class Token
    ALGORITHM = "HS256".freeze

    def self.issue(user, type: "access", ttl: nil)
      ttl ||= type == "refresh" ? 7.days : 30.minutes
      payload = { sub: user.id, role: user.role, type: type, exp: ttl.from_now.to_i, iat: Time.current.to_i }
      JWT.encode(payload, secret, ALGORITHM)
    end

    def self.decode(raw, type: "access")
      payload = JWT.decode(raw, secret, true, algorithm: ALGORITHM).first
      raise JWT::DecodeError, "wrong token type" unless payload["type"] == type
      payload
    end

    def self.secret
      ENV.fetch("JWT_SECRET") { raise "JWT_SECRET must be set" }
    end
  end
end
