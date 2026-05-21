defmodule ElevenLabs.SpeechEngine.ClientWriteTest do
  use ExUnit.Case, async: true

  alias ElevenLabs.SpeechEngine
  alias ElevenLabs.SpeechEngine.{Config, Response}

  defp client(stub), do: ElevenLabs.new(api_key: "sk", req_options: [plug: {Req.Test, stub}])

  test "create/2 POSTs only the provided keys and decodes Response" do
    Req.Test.stub(__MODULE__, fn conn ->
      assert conn.method == "POST"
      assert conn.request_path == "/v1/speech-engine"
      {:ok, raw, conn} = Plug.Conn.read_body(conn)
      body = Jason.decode!(raw)
      assert body["name"] == "Bot"
      assert body["speech_engine"] == %{"ws_url" => "wss://x"}
      refute Map.has_key?(body, "asr")

      Req.Test.json(conn, %{"speech_engine_id" => "seng_9", "name" => "Bot"})
    end)

    assert {:ok, %Response{speech_engine_id: "seng_9", name: "Bot"}} =
             SpeechEngine.create(client(__MODULE__),
               speech_engine: %{ws_url: "wss://x"},
               name: "Bot"
             )
  end

  test "create/2 accepts a %Config{} struct for speech_engine" do
    Req.Test.stub(__MODULE__, fn conn ->
      {:ok, raw, conn} = Plug.Conn.read_body(conn)
      assert Jason.decode!(raw)["speech_engine"] == %{"ws_url" => "wss://z"}
      Req.Test.json(conn, %{"speech_engine_id" => "seng_1", "name" => "n"})
    end)

    assert {:ok, %Response{}} =
             SpeechEngine.create(client(__MODULE__), speech_engine: %Config{ws_url: "wss://z"})
  end

  test "update/3 PATCHes the id path and decodes Response" do
    Req.Test.stub(__MODULE__, fn conn ->
      assert conn.method == "PATCH"
      assert conn.request_path == "/v1/speech-engine/seng_9"
      {:ok, raw, conn} = Plug.Conn.read_body(conn)
      assert Jason.decode!(raw) == %{"name" => "Renamed"}
      Req.Test.json(conn, %{"speech_engine_id" => "seng_9", "name" => "Renamed"})
    end)

    assert {:ok, %Response{name: "Renamed"}} =
             SpeechEngine.update(client(__MODULE__), "seng_9", name: "Renamed")
  end
end
