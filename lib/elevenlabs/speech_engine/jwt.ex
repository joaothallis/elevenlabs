defmodule ElevenLabs.SpeechEngine.JWT do
  @moduledoc """
  Verifies the HS256 JWT that ElevenLabs sends in the
  `X-Elevenlabs-Speech-Engine-Authorization` header. The HMAC secret is the
  SHA-256 hash of the API key.
  """

  @issuer "https://api.elevenlabs.io/convai/speech-engine"
  @subject "convai_speech_engine_upstream"
  @leeway 60

  @doc """
  Verifies `value` (a token, optionally `Bearer `-prefixed) against `api_key`.
  Returns `{:ok, payload}` or `{:error, reason}`.
  """
  @spec verify(String.t(), String.t()) :: {:ok, map()} | {:error, atom()}
  def verify(value, api_key) do
    token = value |> String.trim() |> strip_bearer()

    with [header, body, signature] <- String.split(token, "."),
         {:ok, payload_json} <- Base.url_decode64(body, padding: false),
         {:ok, payload} when is_map(payload) <- Jason.decode(payload_json),
         {:ok, signature_bytes} <- Base.url_decode64(signature, padding: false),
         :ok <- verify_signature(header, body, signature_bytes, api_key),
         :ok <- check_claims(payload) do
      {:ok, payload}
    else
      {:error, reason} when is_atom(reason) -> {:error, reason}
      _ -> {:error, :invalid}
    end
  end

  defp strip_bearer(token) do
    case String.split(token, " ", parts: 2) do
      [scheme, rest] -> if String.downcase(scheme) == "bearer", do: String.trim(rest), else: token
      _ -> token
    end
  end

  defp verify_signature(header, body, signature_bytes, api_key) do
    secret = :crypto.hash(:sha256, String.trim(api_key))
    expected = :crypto.mac(:hmac, :sha256, secret, header <> "." <> body)

    if Plug.Crypto.secure_compare(expected, signature_bytes) do
      :ok
    else
      {:error, :signature_mismatch}
    end
  end

  defp check_claims(payload) do
    now = System.system_time(:second)

    cond do
      payload["iss"] != @issuer -> {:error, :bad_issuer}
      payload["sub"] != @subject -> {:error, :bad_subject}
      not is_number(payload["exp"]) -> {:error, :missing_exp}
      not is_number(payload["iat"]) -> {:error, :missing_iat}
      payload["exp"] + @leeway < now -> {:error, :expired}
      payload["iat"] - @leeway > now -> {:error, :iat_in_future}
      true -> :ok
    end
  end
end
