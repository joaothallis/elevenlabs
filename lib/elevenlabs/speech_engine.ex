defmodule ElevenLabs.SpeechEngine do
  @moduledoc """
  REST CRUD for Speech Engine resources, plus the WebSocket server runtime
  entry points (`serve/2`, `stop/1`, `verify_request/2`).
  """

  alias ElevenLabs.{Client, Error}
  alias ElevenLabs.SpeechEngine.{Config, JWT, ListResponse, Response}
  alias ElevenLabs.SpeechEngine.Server

  @base "v1/speech-engine"
  @list_params [:page_size, :search, :sort_direction, :sort_by, :cursor]
  @body_keys [
    :name,
    :speech_engine,
    :asr,
    :tts,
    :turn,
    :conversation,
    :privacy,
    :call_limits,
    :language,
    :tags,
    :overrides
  ]

  @doc "Lists speech engines. Options: #{inspect(@list_params)}."
  @spec list(Client.t(), keyword()) :: {:ok, ListResponse.t()} | {:error, Error.t()}
  def list(%Client{req: req}, opts \\ []) do
    params = Keyword.take(opts, @list_params)

    req
    |> Req.get(url: @base, params: params)
    |> decode(&ListResponse.from_json/1)
  end

  @doc "Fetches a single speech engine by id."
  @spec get(Client.t(), String.t()) :: {:ok, Response.t()} | {:error, Error.t()}
  def get(%Client{req: req}, id) do
    req
    |> Req.get(url: "#{@base}/#{id}")
    |> decode(&Response.from_json/1)
  end

  @doc "Deletes a speech engine by id."
  @spec delete(Client.t(), String.t()) :: :ok | {:error, Error.t()}
  def delete(%Client{req: req}, id) do
    case Req.delete(req, url: "#{@base}/#{id}") do
      {:ok, %{status: status}} when status in 200..299 -> :ok
      {:ok, %{status: status, body: body}} -> {:error, %Error{status: status, body: body}}
      {:error, reason} -> {:error, %Error{reason: reason}}
    end
  end

  @doc """
  Creates a speech engine. Requires `:speech_engine` (a `Config` or bare map);
  other keys (#{inspect(@body_keys)}) are optional and only sent when present.
  """
  @spec create(Client.t(), keyword()) :: {:ok, Response.t()} | {:error, Error.t()}
  def create(%Client{req: req}, opts) do
    req
    |> Req.post(url: @base, json: build_body(opts))
    |> decode(&Response.from_json/1)
  end

  @doc "Partially updates a speech engine. Only the provided keys are sent."
  @spec update(Client.t(), String.t(), keyword()) :: {:ok, Response.t()} | {:error, Error.t()}
  def update(%Client{req: req}, id, opts) do
    req
    |> Req.patch(url: "#{@base}/#{id}", json: build_body(opts))
    |> decode(&Response.from_json/1)
  end

  @auth_header "x-elevenlabs-speech-engine-authorization"

  @doc """
  Verifies that a request carries a valid Speech Engine authorization header.
  Accepts a `Plug.Conn` or a headers map/list. Returns a boolean.

  Only needed for fully manual WebSocket integration; `ElevenLabs.SpeechEngine.Plug`
  and `serve/2` verify automatically.
  """
  @spec verify_request(Plug.Conn.t() | map() | list(), String.t()) :: boolean()
  def verify_request(%Plug.Conn{} = conn, api_key) do
    case Plug.Conn.get_req_header(conn, @auth_header) do
      [value | _] -> match?({:ok, _}, JWT.verify(value, api_key))
      [] -> false
    end
  end

  def verify_request(headers, api_key) when is_list(headers) do
    headers |> Map.new(fn {k, v} -> {String.downcase(k), v} end) |> verify_request(api_key)
  end

  def verify_request(headers, api_key) when is_map(headers) do
    downcased = Map.new(headers, fn {k, v} -> {String.downcase(to_string(k)), v} end)

    case Map.get(downcased, @auth_header) do
      nil -> false
      value -> match?({:ok, _}, JWT.verify(value, api_key))
    end
  end

  @doc """
  Starts a standalone Speech Engine WebSocket server (Bandit + verifying Plug)
  and returns `{:ok, pid}`.

  The first argument provides the API key used to verify incoming connections —
  pass an `ElevenLabs.Client` or the key string directly. `opts` requires
  `:handler` and accepts `:port` (default 3001), `:path`, `:debug`.
  """
  @spec serve(Client.t() | String.t(), keyword()) :: {:ok, pid()} | {:error, term()}
  def serve(client_or_key, opts) do
    api_key = resolve_api_key(client_or_key, opts)
    Server.start_link(Keyword.put(opts, :api_key, api_key))
  end

  @doc "Stops a server started by `serve/2`."
  @spec stop(pid()) :: :ok
  def stop(pid) when is_pid(pid) do
    # Bandit's listener supervisor terminates with `:shutdown`, which
    # `Supervisor.stop/1` re-raises into the caller; unlink the owner first and
    # catch that exit, then confirm termination via a monitor.
    Process.unlink(pid)
    ref = Process.monitor(pid)

    try do
      Supervisor.stop(pid, :shutdown)
    catch
      :exit, _ -> :ok
    end

    receive do
      {:DOWN, ^ref, :process, ^pid, _reason} -> :ok
    after
      5_000 ->
        Process.demonitor(ref, [:flush])
        :ok
    end
  end

  # --- internal helpers ---

  defp decode({:ok, %{status: status, body: body}}, fun) when status in 200..299,
    do: {:ok, fun.(body)}

  defp decode({:ok, %{status: status, body: body}}, _fun),
    do: {:error, %Error{status: status, body: body}}

  defp decode({:error, reason}, _fun), do: {:error, %Error{reason: reason}}

  defp build_body(opts) do
    for key <- @body_keys, Keyword.has_key?(opts, key), into: %{} do
      {key, encode_value(key, Keyword.fetch!(opts, key))}
    end
  end

  defp encode_value(:speech_engine, value), do: Config.to_map(value)
  defp encode_value(_key, value), do: value

  defp resolve_api_key(%Client{api_key: key}, opts), do: opts[:api_key] || key
  defp resolve_api_key(key, opts) when is_binary(key), do: opts[:api_key] || key
end
