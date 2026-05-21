defmodule ElevenLabs.SpeechEngine.Response do
  @moduledoc """
  A full speech engine resource. The nested config blobs (`asr`, `tts`, `turn`,
  `conversation`, `privacy`, `call_limits`, `overrides`, `metadata`) are kept as
  plain maps rather than typed structs.
  """

  alias ElevenLabs.SpeechEngine.Config

  defstruct [
    :speech_engine_id,
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
    :overrides,
    :metadata
  ]

  @type t :: %__MODULE__{
          speech_engine_id: String.t(),
          name: String.t(),
          speech_engine: Config.t() | nil,
          asr: map() | nil,
          tts: map() | nil,
          turn: map() | nil,
          conversation: map() | nil,
          privacy: map() | nil,
          call_limits: map() | nil,
          language: String.t() | nil,
          tags: [String.t()] | nil,
          overrides: map() | nil,
          metadata: map() | nil
        }

  @spec from_json(map()) :: t()
  def from_json(map) when is_map(map) do
    %__MODULE__{
      speech_engine_id: map["speech_engine_id"],
      name: map["name"],
      speech_engine: map["speech_engine"] && Config.from_json(map["speech_engine"]),
      asr: map["asr"],
      tts: map["tts"],
      turn: map["turn"],
      conversation: map["conversation"],
      privacy: map["privacy"],
      call_limits: map["call_limits"],
      language: map["language"],
      tags: map["tags"],
      overrides: map["overrides"],
      metadata: map["metadata"]
    }
  end
end
