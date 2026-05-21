defmodule ElevenLabs.JWTHelper do
  @moduledoc false

  @issuer "https://api.elevenlabs.io/convai/speech-engine"
  @subject "convai_speech_engine_upstream"

  @doc "A valid claim set, valid for one hour from now."
  def valid_payload do
    now = System.system_time(:second)
    %{"iss" => @issuer, "sub" => @subject, "iat" => now, "exp" => now + 3600}
  end

  @doc "Signs `payload` into an HS256 JWT using the ElevenLabs scheme (secret = sha256(api_key))."
  def sign(payload, api_key) do
    header = b64(Jason.encode!(%{"alg" => "HS256", "typ" => "JWT"}))
    body = b64(Jason.encode!(payload))
    secret = :crypto.hash(:sha256, api_key)
    sig = b64(:crypto.mac(:hmac, :sha256, secret, header <> "." <> body))
    "#{header}.#{body}.#{sig}"
  end

  defp b64(data), do: Base.url_encode64(data, padding: false)
end
