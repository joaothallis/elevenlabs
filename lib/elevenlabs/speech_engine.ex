defmodule ElevenLabs.SpeechEngine do
  @moduledoc """
  REST CRUD for Speech Engine resources, plus the WebSocket server runtime
  entry points (`serve/2`, `stop/1`, `verify_request/2`).
  """

  alias ElevenLabs.{Client, Error}
  alias ElevenLabs.SpeechEngine.{Config, ListResponse, Response}

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
end
