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
  # The test pid is captured once at entry: a task that outlives its test (e.g. the
  # duplicate-skip test, which does not await {:done}) then targets its own finished
  # test process rather than leaking a stray message into a later test.
  @impl true
  def handle_transcript(_transcript, session) do
    pid = TestSupport.test_pid()
    send(pid, {:start, session.event_id})
    Process.sleep(300)
    send(pid, {:done, session.event_id})
  end
end
