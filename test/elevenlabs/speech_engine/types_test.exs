defmodule ElevenLabs.SpeechEngine.TypesTest do
  use ExUnit.Case, async: true

  alias ElevenLabs.SpeechEngine.{
    Config,
    ConversationMessage,
    ListResponse,
    Response,
    SummaryResponse
  }

  test "Config round-trips through from_json and to_map" do
    assert %Config{ws_url: "wss://x", request_headers: %{"a" => 1}} =
             Config.from_json(%{"ws_url" => "wss://x", "request_headers" => %{"a" => 1}})

    assert Config.to_map(%Config{ws_url: "wss://x"}) == %{ws_url: "wss://x"}

    assert Config.to_map(%Config{ws_url: "wss://x", request_headers: %{"a" => 1}}) ==
             %{ws_url: "wss://x", request_headers: %{"a" => 1}}

    assert Config.to_map(%{ws_url: "wss://y"}) == %{ws_url: "wss://y"}
  end

  test "ConversationMessage.from_json/1" do
    assert %ConversationMessage{role: "user", content: "hi"} =
             ConversationMessage.from_json(%{"role" => "user", "content" => "hi"})
  end

  test "SummaryResponse.from_json/1" do
    assert %SummaryResponse{
             speech_engine_id: "seng_1",
             name: "A",
             created_at_unix_secs: 5,
             tags: ["t"]
           } =
             SummaryResponse.from_json(%{
               "speech_engine_id" => "seng_1",
               "name" => "A",
               "created_at_unix_secs" => 5,
               "tags" => ["t"]
             })
  end

  test "ListResponse.from_json/1 maps nested summaries" do
    assert %ListResponse{
             speech_engines: [%SummaryResponse{speech_engine_id: "seng_1"}],
             next_cursor: "c",
             has_more: true
           } =
             ListResponse.from_json(%{
               "speech_engines" => [
                 %{
                   "speech_engine_id" => "seng_1",
                   "name" => "A",
                   "created_at_unix_secs" => 1,
                   "tags" => []
                 }
               ],
               "next_cursor" => "c",
               "has_more" => true
             })
  end

  test "Response.from_json/1 types the top level and keeps config blobs as maps" do
    resp =
      Response.from_json(%{
        "speech_engine_id" => "seng_1",
        "name" => "Bot",
        "speech_engine" => %{"ws_url" => "wss://x"},
        "asr" => %{"quality" => "high"},
        "tts" => %{"voice_id" => "v"},
        "language" => "en",
        "tags" => ["a"],
        "metadata" => %{"created_at_unix_secs" => 9}
      })

    assert resp.speech_engine_id == "seng_1"
    assert %Config{ws_url: "wss://x"} = resp.speech_engine
    assert resp.asr == %{"quality" => "high"}
    assert resp.metadata == %{"created_at_unix_secs" => 9}
  end
end
