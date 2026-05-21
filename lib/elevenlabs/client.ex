defmodule ElevenLabs.Client do
  @moduledoc """
  Holds configuration for talking to the ElevenLabs API: the API key, base URL,
  and a preconfigured `Req` request. Build one with `ElevenLabs.new/1`.
  """

  defstruct [:api_key, :base_url, :req]

  @type t :: %__MODULE__{
          api_key: String.t() | nil,
          base_url: String.t(),
          req: Req.Request.t()
        }
end
