defmodule ElevenLabs.SpeechEngine.SessionLifecycleTest do
  use ExUnit.Case, async: false

  alias ElevenLabs.SpeechEngine.Session
  alias ElevenLabs.TestSupport
  import ElevenLabs.TestSupport, only: [frame: 1]

  setup do
    TestSupport.set_test_pid(self())
    {:ok, state} = Session.init(%{handler: ElevenLabs.RecordingHandler})
    %{state: state}
  end

  test "init/1 builds initial state", %{state: state} do
    assert state.handler == ElevenLabs.RecordingHandler
    assert state.conversation_id == nil
    assert state.current_task == nil
    assert state.current_event_id == nil
  end

  test "init message sets conversation_id and calls handle_init", %{state: state} do
    assert {:ok, new_state} =
             Session.handle_in(frame(%{type: "init", conversation_id: "conv_1"}), state)

    assert new_state.conversation_id == "conv_1"
    assert_receive {:handle_init, "conv_1"}
  end

  test "ping message pushes a pong", %{state: state} do
    assert {:push, {:text, json}, ^state} = Session.handle_in(frame(%{type: "ping"}), state)
    assert Jason.decode!(json) == %{"type" => "pong"}
  end

  test "close message stops the connection", %{state: state} do
    assert {:stop, :normal, _state} = Session.handle_in(frame(%{type: "close"}), state)
  end

  test "error message calls handle_error", %{state: state} do
    assert {:ok, ^state} = Session.handle_in(frame(%{type: "error", message: "boom"}), state)
    assert_receive {:handle_error, {:remote_error, "boom"}}
  end

  test "unknown message types are ignored", %{state: state} do
    assert {:ok, ^state} = Session.handle_in(frame(%{type: "totally_new_thing"}), state)
  end

  test "malformed JSON is ignored", %{state: state} do
    assert {:ok, ^state} = Session.handle_in({"{not json", [opcode: :text]}, state)
  end

  test "terminate calls handle_close", %{state: state} do
    assert :ok = Session.terminate(:remote, state)
    assert_receive :handle_close
  end
end
