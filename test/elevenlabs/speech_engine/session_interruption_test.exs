defmodule ElevenLabs.SpeechEngine.SessionInterruptionTest do
  use ExUnit.Case, async: false

  alias ElevenLabs.SpeechEngine.Session
  alias ElevenLabs.TestSupport
  import ElevenLabs.TestSupport, only: [frame: 1]

  setup do
    TestSupport.set_test_pid(self())
    # RecordingHandler.handle_transcript sends {:start, id}, sleeps 300ms, then {:done, id}.
    {:ok, state} = Session.init(%{handler: ElevenLabs.RecordingHandler})
    %{state: state}
  end

  defp transcript(event_id) do
    frame(%{
      type: "user_transcript",
      event_id: event_id,
      user_transcript: [%{role: "user", content: "hi"}]
    })
  end

  test "a new transcript cancels the in-flight handler", %{state: state} do
    {:ok, state} = Session.handle_in(transcript(1), state)
    assert_receive {:start, 1}, 500

    # interrupt before the first handler finishes its 300ms sleep
    {:ok, state} = Session.handle_in(transcript(2), state)
    assert_receive {:start, 2}, 500

    assert state.current_event_id == 2
    refute_receive {:done, 1}, 600
    assert_receive {:done, 2}, 1000
  end

  test "a duplicate transcript (same event_id, task alive) is skipped", %{state: state} do
    {:ok, state} = Session.handle_in(transcript(1), state)
    assert_receive {:start, 1}, 500
    first_task = state.current_task

    {:ok, state} = Session.handle_in(transcript(1), state)
    # same task kept, handler not started again
    assert state.current_task == first_task
    refute_receive {:start, 1}, 200
  end
end
