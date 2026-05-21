defmodule ElevenLabs.SpeechEngine.ClientReadTest do
  use ExUnit.Case, async: true

  alias ElevenLabs.SpeechEngine
  alias ElevenLabs.SpeechEngine.{ListResponse, Response, SummaryResponse}

  defp client(stub), do: ElevenLabs.new(api_key: "sk", req_options: [plug: {Req.Test, stub}])

  test "list/2 issues GET with params and decodes ListResponse" do
    Req.Test.stub(__MODULE__, fn conn ->
      assert conn.method == "GET"
      assert conn.request_path == "/v1/speech-engine"
      conn = Plug.Conn.fetch_query_params(conn)
      assert conn.query_params["page_size"] == "2"
      assert conn.query_params["search"] == "bot"

      Req.Test.json(conn, %{
        "speech_engines" => [
          %{
            "speech_engine_id" => "seng_1",
            "name" => "A",
            "created_at_unix_secs" => 1,
            "tags" => []
          }
        ],
        "next_cursor" => "c2",
        "has_more" => true
      })
    end)

    assert {:ok,
            %ListResponse{
              speech_engines: [%SummaryResponse{speech_engine_id: "seng_1"}],
              next_cursor: "c2",
              has_more: true
            }} =
             SpeechEngine.list(client(__MODULE__), page_size: 2, search: "bot")
  end

  test "get/2 issues GET to the id path and decodes Response" do
    Req.Test.stub(__MODULE__, fn conn ->
      assert conn.method == "GET"
      assert conn.request_path == "/v1/speech-engine/seng_1"
      Req.Test.json(conn, %{"speech_engine_id" => "seng_1", "name" => "A"})
    end)

    assert {:ok, %Response{speech_engine_id: "seng_1", name: "A"}} =
             SpeechEngine.get(client(__MODULE__), "seng_1")
  end

  test "delete/2 returns :ok on success" do
    Req.Test.stub(__MODULE__, fn conn ->
      assert conn.method == "DELETE"
      assert conn.request_path == "/v1/speech-engine/seng_1"
      Plug.Conn.send_resp(conn, 200, "")
    end)

    assert :ok = SpeechEngine.delete(client(__MODULE__), "seng_1")
  end

  test "non-2xx maps to {:error, %Error{}}" do
    Req.Test.stub(__MODULE__, fn conn ->
      conn |> Plug.Conn.put_status(404) |> Req.Test.json(%{"detail" => "missing"})
    end)

    assert {:error, %ElevenLabs.Error{status: 404, body: %{"detail" => "missing"}}} =
             SpeechEngine.get(client(__MODULE__), "seng_x")
  end
end
