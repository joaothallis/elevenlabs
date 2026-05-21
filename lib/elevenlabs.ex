defmodule ElevenLabs do
  @moduledoc """
  Entry point for the ElevenLabs Speech Engine SDK.

  Build a client with `new/1`, then call the functions in
  `ElevenLabs.SpeechEngine`.
  """

  alias ElevenLabs.Client

  @default_base_url "https://api.elevenlabs.io"

  @doc """
  Builds an `ElevenLabs.Client`.

  Options:
    * `:api_key` — defaults to the `ELEVENLABS_API_KEY` environment variable.
    * `:base_url` — defaults to `#{@default_base_url}`.
    * `:req_options` — extra options merged into `Req.new/1` (useful for tests).
  """
  @spec new(keyword()) :: Client.t()
  def new(opts \\ []) do
    api_key = opts[:api_key] || System.get_env("ELEVENLABS_API_KEY")
    base_url = opts[:base_url] || @default_base_url
    req_options = Keyword.get(opts, :req_options, [])

    req =
      [base_url: base_url]
      |> Keyword.merge(req_options)
      |> Req.new()
      |> put_api_key(api_key)

    %Client{api_key: api_key, base_url: base_url, req: req}
  end

  defp put_api_key(req, nil), do: req
  defp put_api_key(req, key), do: Req.Request.put_header(req, "xi-api-key", key)
end
