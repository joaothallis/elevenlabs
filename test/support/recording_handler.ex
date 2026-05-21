defmodule ElevenLabs.RecordingHandler do
  @moduledoc false
  use ElevenLabs.SpeechEngine.Handler

  alias ElevenLabs.TestSupport

  @impl true
  def handle_init(conversation_id, _session) do
    send(TestSupport.test_pid(), {:handle_init, conversation_id})
  end

  @impl true
  def handle_close(_session) do
    send(TestSupport.test_pid(), :handle_close)
  end

  @impl true
  def handle_error(error, _session) do
    send(TestSupport.test_pid(), {:handle_error, error})
  end

  # Sends {:start, event_id}, sleeps, then {:done, event_id}. Used to test interruption.
  @impl true
  def handle_transcript(_transcript, session) do
    send(TestSupport.test_pid(), {:start, session.event_id})
    Process.sleep(300)
    send(TestSupport.test_pid(), {:done, session.event_id})
  end
end
