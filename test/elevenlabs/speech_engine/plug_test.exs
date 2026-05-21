defmodule ElevenLabs.SpeechEngine.PlugTest do
  use ExUnit.Case, async: true
  import Plug.Test
  import Plug.Conn

  alias ElevenLabs.SpeechEngine
  alias ElevenLabs.SpeechEngine.Plug, as: SEPlug
  alias ElevenLabs.JWTHelper

  @api_key "sk_plug"
  @header "x-elevenlabs-speech-engine-authorization"

  defp opts(extra \\ []) do
    SEPlug.init(Keyword.merge([api_key: @api_key, handler: ElevenLabs.RecordingHandler], extra))
  end

  test "missing auth header -> 401" do
    conn = conn(:get, "/") |> SEPlug.call(opts())
    assert conn.status == 401
    assert conn.halted
  end

  test "invalid token -> 401" do
    conn =
      conn(:get, "/")
      |> put_req_header(@header, "Bearer nope")
      |> SEPlug.call(opts())

    assert conn.status == 401
  end

  test "path mismatch -> 404" do
    token = JWTHelper.sign(JWTHelper.valid_payload(), @api_key)

    conn =
      conn(:get, "/wrong")
      |> put_req_header(@header, token)
      |> SEPlug.call(opts(path: "/ws"))

    assert conn.status == 404
  end

  defp ws_conn(path) do
    conn(:get, path)
    |> Map.update!(:req_headers, fn headers ->
      [{"host", "localhost"} | headers]
    end)
    |> put_req_header("connection", "upgrade")
    |> put_req_header("upgrade", "websocket")
    |> put_req_header("sec-websocket-key", Base.encode64("0123456789abcdef"))
    |> put_req_header("sec-websocket-version", "13")
  end

  test "valid token -> connection is upgraded" do
    token = JWTHelper.sign(JWTHelper.valid_payload(), @api_key)

    conn =
      ws_conn("/")
      |> put_req_header(@header, token)
      |> SEPlug.call(opts())

    assert conn.state == :upgraded
  end

  test "verify_request/2 accepts a conn with a valid token" do
    token = JWTHelper.sign(JWTHelper.valid_payload(), @api_key)
    conn = conn(:get, "/") |> put_req_header(@header, token)
    assert SpeechEngine.verify_request(conn, @api_key) == true
    assert SpeechEngine.verify_request(conn(:get, "/"), @api_key) == false
  end
end
