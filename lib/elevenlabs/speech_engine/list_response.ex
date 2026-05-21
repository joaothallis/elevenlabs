defmodule ElevenLabs.SpeechEngine.ListResponse do
  @moduledoc "Paginated list of speech engines."

  alias ElevenLabs.SpeechEngine.SummaryResponse

  defstruct [:speech_engines, :next_cursor, :has_more]

  @type t :: %__MODULE__{
          speech_engines: [SummaryResponse.t()],
          next_cursor: String.t() | nil,
          has_more: boolean()
        }

  @spec from_json(map()) :: t()
  def from_json(map) when is_map(map) do
    %__MODULE__{
      speech_engines: Enum.map(map["speech_engines"] || [], &SummaryResponse.from_json/1),
      next_cursor: map["next_cursor"],
      has_more: map["has_more"]
    }
  end
end
