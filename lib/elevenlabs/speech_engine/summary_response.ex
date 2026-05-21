defmodule ElevenLabs.SpeechEngine.SummaryResponse do
  @moduledoc "A speech engine as returned in a list response."

  defstruct [:speech_engine_id, :name, :created_at_unix_secs, :tags]

  @type t :: %__MODULE__{
          speech_engine_id: String.t(),
          name: String.t(),
          created_at_unix_secs: integer(),
          tags: [String.t()]
        }

  @spec from_json(map()) :: t()
  def from_json(map) when is_map(map) do
    %__MODULE__{
      speech_engine_id: map["speech_engine_id"],
      name: map["name"],
      created_at_unix_secs: map["created_at_unix_secs"],
      tags: map["tags"]
    }
  end
end
