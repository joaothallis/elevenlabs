defmodule ElevenLabs.SpeechEngine.ConversationMessage do
  @moduledoc "A single message in a speech engine conversation."

  defstruct [:role, :content]

  @type t :: %__MODULE__{role: String.t(), content: String.t()}

  @spec from_json(map()) :: t()
  def from_json(map) when is_map(map) do
    %__MODULE__{role: map["role"], content: map["content"]}
  end
end
