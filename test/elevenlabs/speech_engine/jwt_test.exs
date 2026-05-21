defmodule ElevenLabs.SpeechEngine.JWTTest do
  use ExUnit.Case, async: true

  alias ElevenLabs.SpeechEngine.JWT
  alias ElevenLabs.JWTHelper

  @api_key "sk_secret"

  test "accepts a valid token" do
    token = JWTHelper.sign(JWTHelper.valid_payload(), @api_key)
    assert {:ok, payload} = JWT.verify(token, @api_key)
    assert payload["sub"] == "convai_speech_engine_upstream"
  end

  test "strips a Bearer prefix" do
    token = "Bearer " <> JWTHelper.sign(JWTHelper.valid_payload(), @api_key)
    assert {:ok, _} = JWT.verify(token, @api_key)
  end

  test "rejects a signature signed with the wrong key" do
    token = JWTHelper.sign(JWTHelper.valid_payload(), "wrong_key")
    assert {:error, :signature_mismatch} = JWT.verify(token, @api_key)
  end

  test "rejects a wrong issuer" do
    payload = %{JWTHelper.valid_payload() | "iss" => "https://evil.example"}
    token = JWTHelper.sign(payload, @api_key)
    assert {:error, :bad_issuer} = JWT.verify(token, @api_key)
  end

  test "rejects a wrong subject" do
    payload = %{JWTHelper.valid_payload() | "sub" => "nope"}
    token = JWTHelper.sign(payload, @api_key)
    assert {:error, :bad_subject} = JWT.verify(token, @api_key)
  end

  test "rejects an expired token beyond leeway" do
    now = System.system_time(:second)
    payload = %{JWTHelper.valid_payload() | "iat" => now - 7200, "exp" => now - 120}
    token = JWTHelper.sign(payload, @api_key)
    assert {:error, :expired} = JWT.verify(token, @api_key)
  end

  test "rejects an iat in the future beyond leeway" do
    now = System.system_time(:second)
    payload = %{JWTHelper.valid_payload() | "iat" => now + 120, "exp" => now + 3600}
    token = JWTHelper.sign(payload, @api_key)
    assert {:error, :iat_in_future} = JWT.verify(token, @api_key)
  end

  test "rejects a malformed token" do
    assert {:error, _} = JWT.verify("not.a.jwt.token", @api_key)
    assert {:error, _} = JWT.verify("onlyonepart", @api_key)
  end
end
