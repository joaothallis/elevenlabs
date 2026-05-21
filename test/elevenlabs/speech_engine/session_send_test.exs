defmodule ElevenLabs.SpeechEngine.SessionSendTest do
  use ExUnit.Case, async: true
  import ExUnit.CaptureLog

  alias ElevenLabs.SpeechEngine.Session

  defp session(event_id), do: %Session{conn: self(), event_id: event_id, conversation_id: "c1"}

  test "string response sends content then a final empty marker" do
    assert :ok = Session.send_response(session(7), "Hello world")
    assert_received {:se_chunk, 7, "Hello world", false}
    assert_received {:se_chunk, 7, "", true}
  end

  test "enumerable response streams each binary then a final marker" do
    assert :ok = Session.send_response(session(3), ["Hel", "lo"])
    assert_received {:se_chunk, 3, "Hel", false}
    assert_received {:se_chunk, 3, "lo", false}
    assert_received {:se_chunk, 3, "", true}
  end

  test "empty deltas in a stream are skipped" do
    assert :ok = Session.send_response(session(1), ["a", "", "b"])
    assert_received {:se_chunk, 1, "a", false}
    assert_received {:se_chunk, 1, "b", false}
    assert_received {:se_chunk, 1, "", true}
    refute_received {:se_chunk, 1, "", false}
  end

  test "calling outside a transcript context (event_id nil) warns and is a no-op" do
    log =
      capture_log(fn ->
        assert :ok = Session.send_response(%Session{conn: self(), event_id: nil}, "hi")
      end)

    assert log =~ "send_response"
    refute_received {:se_chunk, _, _, _}
  end

  test "conversation_id/1 reads the handle" do
    assert Session.conversation_id(session(1)) == "c1"
  end
end
