defmodule ElevenLabs.CrashHandler do
  @moduledoc false
  use ElevenLabs.SpeechEngine.Handler

  alias ElevenLabs.TestSupport

  @impl true
  def handle_transcript(_transcript, _session) do
    raise "boom"
  end

  @impl true
  def handle_error(error, _session) do
    send(TestSupport.test_pid(), {:handle_error, error})
  end
end
