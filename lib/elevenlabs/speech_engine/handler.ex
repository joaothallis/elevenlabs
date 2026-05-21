defmodule ElevenLabs.SpeechEngine.Handler do
  @moduledoc """
  Behaviour for Speech Engine conversation handlers.

  Only `c:handle_transcript/2` is required. `use ElevenLabs.SpeechEngine.Handler`
  injects overridable no-op defaults for the other three callbacks.

      defmodule MyAgent do
        use ElevenLabs.SpeechEngine.Handler
        alias ElevenLabs.SpeechEngine.Session

        @impl true
        def handle_transcript(transcript, session) do
          Session.send_response(session, MyLLM.stream(transcript))
        end
      end
  """

  alias ElevenLabs.SpeechEngine.{ConversationMessage, Session}

  @doc "Called once when the conversation starts. Runs in the connection process — keep it quick."
  @callback handle_init(conversation_id :: String.t(), session :: Session.t()) :: any()

  @doc "Called for each user transcript. Runs in a cancellable Task; call `Session.send_response/2` here."
  @callback handle_transcript(transcript :: [ConversationMessage.t()], session :: Session.t()) ::
              any()

  @doc "Called when the conversation ends or the socket disconnects."
  @callback handle_close(session :: Session.t()) :: any()

  @doc "Called on a protocol error or when a transcript handler crashes."
  @callback handle_error(error :: term(), session :: Session.t()) :: any()

  @optional_callbacks handle_init: 2, handle_close: 1, handle_error: 2

  defmacro __using__(_opts) do
    quote do
      @behaviour ElevenLabs.SpeechEngine.Handler

      @impl true
      def handle_init(_conversation_id, _session), do: :ok

      @impl true
      def handle_close(_session), do: :ok

      @impl true
      def handle_error(_error, _session), do: :ok

      defoverridable handle_init: 2, handle_close: 1, handle_error: 2
    end
  end
end
