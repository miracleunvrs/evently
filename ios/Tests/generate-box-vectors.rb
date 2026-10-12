# Prints NaCl box test vectors produced by libsodium (RbNaCl), the reference for ios/Tests/vectors.json.
# Run inside the API container, then merge the output into the "box" key:
#   docker exec -i evently-api-1 bundle exec ruby - < ios/Tests/generate-box-vectors.rb
require "rbnacl"
require "digest"
require "json"

hex = ->(value) { value.unpack1("H*") }
vectors = [ 0, 1, 15, 16, 17, 63, 64, 65, 300, 1500 ].each_with_index.map do |length, index|
  ours = RbNaCl::PrivateKey.new(Digest::SHA256.digest("ours-#{index}"))
  theirs = RbNaCl::PrivateKey.new(Digest::SHA256.digest("theirs-#{index}"))
  nonce = Digest::SHA256.digest("nonce-#{index}")[0, 24]
  message = (Digest::SHA256.digest("message-#{index}") * (length / 32 + 1))[0, length]
  {
    secretKey: hex.(ours.to_bytes), publicKey: hex.(ours.public_key.to_bytes),
    peerSecretKey: hex.(theirs.to_bytes), peerPublicKey: hex.(theirs.public_key.to_bytes),
    nonce: hex.(nonce), message: hex.(message),
    box: hex.(RbNaCl::Box.new(theirs.public_key, ours).encrypt(nonce, message))
  }
end
puts JSON.generate(vectors)
