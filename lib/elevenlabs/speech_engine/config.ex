defmodule ElevenLabs.SpeechEngine.Config do
  @moduledoc "WebSocket connection settings for the upstream transcript server."

  defstruct [:ws_url, :request_headers]

  @type t :: %__MODULE__{ws_url: String.t(), request_headers: map() | nil}

  @doc "Builds a `Config` from a decoded JSON map (string keys)."
  @spec from_json(map()) :: t()
  def from_json(%{"ws_url" => ws_url} = map) do
    %__MODULE__{ws_url: ws_url, request_headers: map["request_headers"]}
  end

  @doc "Converts a `Config` (or bare map) into a JSON-encodable map, dropping nil fields."
  @spec to_map(t() | map()) :: map()
  def to_map(%__MODULE__{ws_url: ws_url, request_headers: nil}), do: %{ws_url: ws_url}

  def to_map(%__MODULE__{ws_url: ws_url, request_headers: rh}),
    do: %{ws_url: ws_url, request_headers: rh}

  def to_map(map) when is_map(map), do: map
end
