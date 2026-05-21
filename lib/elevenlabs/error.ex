defmodule ElevenLabs.Error do
  @moduledoc """
  Represents a failed ElevenLabs API call.

  `status` and `body` are set for non-2xx HTTP responses; `reason` is set for
  transport-level failures (the underlying exception).
  """

  defexception [:status, :body, :reason]

  @type t :: %__MODULE__{status: pos_integer() | nil, body: term(), reason: term()}

  @impl true
  def message(%__MODULE__{status: status, body: body}) when not is_nil(status) do
    "ElevenLabs API error (status #{status}): #{inspect(body)}"
  end

  def message(%__MODULE__{reason: reason}) do
    "ElevenLabs request failed: #{inspect(reason)}"
  end
end
