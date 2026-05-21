defmodule ElevenLabs.ResponderHandler do
  @moduledoc false
  use ElevenLabs.SpeechEngine.Handler

  alias ElevenLabs.SpeechEngine.Session
  alias ElevenLabs.TestSupport

  @impl true
  def handle_transcript(transcript, session) do
    send(TestSupport.test_pid(), {:got_transcript, transcript})
    Session.send_response(session, ["Hel", "lo"])
  end
end
