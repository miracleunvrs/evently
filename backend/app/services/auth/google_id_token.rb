module Auth
  class GoogleIdToken
    class Invalid < StandardError; end
    class NotConfigured < StandardError; end

    CERTS_URL = "https://www.googleapis.com/oauth2/v3/certs".freeze
    ISSUERS = %w[accounts.google.com https://accounts.google.com].freeze
    CERTS_TTL = 1.hour
    # Public OAuth client ID of the Evently iOS app; GOOGLE_CLIENT_IDS overrides the list.
    IOS_CLIENT_ID = "767882385413-2vc39fer33r262rokvbjf0k0v00tcdul.apps.googleusercontent.com".freeze

    def self.client_ids
      ENV.fetch("GOOGLE_CLIENT_IDS", IOS_CLIENT_ID).split(",").map(&:strip).reject(&:empty?)
    end

    def initialize(client_ids: self.class.client_ids, keys: nil)
      @client_ids = client_ids
      @keys = keys
    end

    def verify!(raw)
      raise NotConfigured, "GOOGLE_CLIENT_IDS must be set" if @client_ids.empty?

      payload = JWT.decode(raw.to_s, nil, true,
        algorithms: [ "RS256" ], jwks: jwks,
        iss: ISSUERS, verify_iss: true,
        aud: @client_ids, verify_aud: true).first
      raise Invalid, "subject is missing" if payload["sub"].blank?
      raise Invalid, "email is not verified" unless payload["email"].present? && payload["email_verified"].in?([ true, "true" ])

      payload
    rescue JWT::DecodeError => error
      raise Invalid, error.message
    end

    private

    def jwks
      return @keys if @keys

      ->(options) { self.class.certs(force: options[:kid_not_found]) }
    end

    # Google rotates signing keys, so a token signed by an unknown key triggers one refetch.
    def self.certs(force: false)
      @certs = nil if force || @certs_expire_at.nil? || @certs_expire_at.past?
      @certs ||= begin
        response = Faraday.get(CERTS_URL) { |request| request.options.timeout = 5 }
        raise Invalid, "Google keys are unavailable" unless response.success?

        @certs_expire_at = CERTS_TTL.from_now
        JWT::JWK::Set.new(JSON.parse(response.body))
      end
    rescue Faraday::Error, JSON::ParserError
      raise Invalid, "Google keys are unavailable"
    end
  end
end
