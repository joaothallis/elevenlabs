defmodule ElevenLabs.TestHandler do
  @moduledoc false
  use ElevenLabs.SpeechEngine.Handler

  alias ElevenLabs.SpeechEngine.Session

  @impl true
  def handle_transcript(_transcript, session) do
    Session.send_response(session, "hi there")
  end
end
