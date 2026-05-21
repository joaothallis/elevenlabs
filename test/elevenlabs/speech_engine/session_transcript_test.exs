defmodule ElevenLabs.SpeechEngine.SessionTranscriptTest do
  use ExUnit.Case, async: false

  alias ElevenLabs.SpeechEngine.{ConversationMessage, Session}
  alias ElevenLabs.TestSupport
  import ElevenLabs.TestSupport, only: [frame: 1]

  setup do
    TestSupport.set_test_pid(self())
    {:ok, state} = Session.init(%{handler: ElevenLabs.ResponderHandler})
    %{state: state}
  end

  test "user_transcript parses messages, spawns the handler, and tracks event_id", %{state: state} do
    msg = %{
      type: "user_transcript",
      event_id: 5,
      user_transcript: [%{role: "user", content: "hi"}]
    }

    assert {:ok, new_state} = Session.handle_in(frame(msg), state)

    assert new_state.current_event_id == 5
    assert new_state.current_task != nil

    assert_receive {:got_transcript, [%ConversationMessage{role: "user", content: "hi"}]}
    # send_response chunks are delivered to the connection process (here, the test process)
    assert_receive {:se_chunk, 5, "Hel", false}
    assert_receive {:se_chunk, 5, "lo", false}
    assert_receive {:se_chunk, 5, "", true}
  end

  test "handle_info pushes an agent_response frame for the current event_id", %{state: state} do
    state = %{state | current_event_id: 7}

    assert {:push, {:text, json}, ^state} =
             Session.handle_info({:se_chunk, 7, "hi", false}, state)

    assert Jason.decode!(json) == %{
             "type" => "agent_response",
             "content" => "hi",
             "event_id" => 7,
             "is_final" => false
           }
  end

  test "handle_info drops chunks whose event_id is stale", %{state: state} do
    state = %{state | current_event_id: 7}
    assert {:ok, ^state} = Session.handle_info({:se_chunk, 6, "stale", false}, state)
  end
end
