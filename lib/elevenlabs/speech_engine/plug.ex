defmodule ElevenLabs.SpeechEngine.Plug do
  @moduledoc """
  A Plug that verifies the ElevenLabs Speech Engine authorization header and, on
  success, upgrades the connection to an `ElevenLabs.SpeechEngine.Session`
  WebSocket.

  Mount it in any Plug/Phoenix router:

      forward "/speech-engine/ws", to: ElevenLabs.SpeechEngine.Plug,
        init_opts: [api_key: System.fetch_env!("ELEVENLABS_API_KEY"), handler: MyAgent]

  Options: `:api_key` (required), `:handler` (required), `:path` (optional exact
  path to enforce), `:debug` (optional boolean).
  """

  @behaviour Plug

  import Plug.Conn

  alias ElevenLabs.SpeechEngine.{JWT, Session}

  @auth_header "x-elevenlabs-speech-engine-authorization"

  @impl true
  def init(opts) do
    %{
      api_key: Keyword.fetch!(opts, :api_key),
      handler: Keyword.fetch!(opts, :handler),
      path: Keyword.get(opts, :path),
      debug: Keyword.get(opts, :debug, false)
    }
  end

  @impl true
  def call(conn, %{api_key: api_key, handler: handler, path: path, debug: debug}) do
    cond do
      path != nil and conn.request_path != path ->
        conn |> send_resp(404, "not found\n") |> halt()

      not authorized?(conn, api_key) ->
        conn |> send_resp(401, "authorization failed\n") |> halt()

      true ->
        conn
        |> WebSockAdapter.upgrade(Session, %{handler: handler, debug: debug}, timeout: 60_000)
        |> halt()
    end
  end

  defp authorized?(conn, api_key) do
    case get_req_header(conn, @auth_header) do
      [value | _] -> match?({:ok, _}, JWT.verify(value, api_key))
      [] -> false
    end
  end
end
