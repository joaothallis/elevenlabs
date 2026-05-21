defmodule ElevenLabs.SpeechEngine.SessionTaskTest do
  use ExUnit.Case, async: false

  alias ElevenLabs.SpeechEngine.Session
  alias ElevenLabs.TestSupport
  import ElevenLabs.TestSupport, only: [frame: 1]

  test "a normal task result clears current_task" do
    TestSupport.set_test_pid(self())
    {:ok, state} = Session.init(%{handler: ElevenLabs.ResponderHandler})

    msg = %{
      type: "user_transcript",
      event_id: 1,
      user_transcript: [%{role: "user", content: "hi"}]
    }

    {:ok, state} = Session.handle_in(frame(msg), state)
    task = state.current_task

    # the async_nolink task sends {ref, result} when it finishes
    assert_receive {ref, _result} when ref == task.ref, 1000
    assert {:ok, cleared} = Session.handle_info({task.ref, :done}, state)
    assert cleared.current_task == nil
  end

  test "a crashed task triggers handle_error and pushes a final marker" do
    TestSupport.set_test_pid(self())
    {:ok, state} = Session.init(%{handler: ElevenLabs.CrashHandler})
    state = %{state | conversation_id: "c1"}

    msg = %{
      type: "user_transcript",
      event_id: 4,
      user_transcript: [%{role: "user", content: "hi"}]
    }

    {:ok, state} = Session.handle_in(frame(msg), state)
    task = state.current_task

    assert_receive {:DOWN, ref, :process, _pid, reason} when ref == task.ref, 1000
    refute reason == :normal

    assert {:push, {:text, json}, cleared} =
             Session.handle_info({:DOWN, task.ref, :process, task.pid, reason}, state)

    assert cleared.current_task == nil
    decoded = Jason.decode!(json)
    assert decoded["type"] == "agent_response"
    assert decoded["is_final"] == true
    assert decoded["event_id"] == 4
    assert_receive {:handle_error, {:handler_crashed, _}}
  end
end
