defmodule ElevenLabs.SpeechEngine.EndToEndTest do
  use ExUnit.Case, async: false

  alias ElevenLabs.SpeechEngine
  alias ElevenLabs.JWTHelper

  @api_key "sk_e2e"
  @header "x-elevenlabs-speech-engine-authorization"

  setup do
    port = free_port()
    {:ok, pid} = SpeechEngine.serve(@api_key, handler: ElevenLabs.TestHandler, port: port)
    on_exit(fn -> if Process.alive?(pid), do: SpeechEngine.stop(pid) end)
    %{port: port}
  end

  test "rejects a connection with an invalid token", %{port: port} do
    {:ok, conn} = Mint.HTTP.connect(:http, "localhost", port)
    {:ok, conn, ref} = Mint.WebSocket.upgrade(:ws, conn, "/", [{@header, "Bearer garbage"}])
    assert recv_status(conn, ref) == 401
  end

  test "accepts a valid token and round-trips a transcript", %{port: port} do
    token = JWTHelper.sign(JWTHelper.valid_payload(), @api_key)
    {:ok, conn} = Mint.HTTP.connect(:http, "localhost", port)
    {:ok, conn, ref} = Mint.WebSocket.upgrade(:ws, conn, "/", [{@header, token}])
    {:ok, conn, websocket} = accept_upgrade(conn, ref)

    {conn, websocket} =
      send_json(conn, websocket, ref, %{type: "init", conversation_id: "conv_1"})

    {conn, websocket} =
      send_json(conn, websocket, ref, %{
        type: "user_transcript",
        event_id: 1,
        user_transcript: [%{role: "user", content: "hello"}]
      })

    texts = recv_text_frames(conn, websocket, ref, [], 2000)
    decoded = Enum.map(texts, &Jason.decode!/1)

    assert Enum.any?(decoded, &(&1["type"] == "agent_response" and &1["content"] == "hi there"))
    assert Enum.any?(decoded, &(&1["type"] == "agent_response" and &1["is_final"] == true))
  end

  # --- helpers ---

  defp free_port do
    {:ok, socket} = :gen_tcp.listen(0, [])
    {:ok, port} = :inet.port(socket)
    :gen_tcp.close(socket)
    port
  end

  # Reads the HTTP status of the upgrade response (for the rejection case).
  defp recv_status(conn, ref) do
    receive do
      message ->
        {:ok, _conn, responses} = Mint.WebSocket.stream(conn, message)

        case Enum.find_value(responses, fn
               {:status, ^ref, status} -> status
               _ -> nil
             end) do
          nil -> recv_status(conn, ref)
          status -> status
        end
    after
      2000 -> flunk("no HTTP status received")
    end
  end

  # Drains the upgrade response and builds the websocket (for the success case).
  defp accept_upgrade(conn, ref) do
    receive do
      message ->
        {:ok, conn, responses} = Mint.WebSocket.stream(conn, message)

        status =
          Enum.find_value(responses, fn
            {:status, ^ref, s} -> s
            _ -> nil
          end)

        headers =
          Enum.find_value(responses, fn
            {:headers, ^ref, h} -> h
            _ -> nil
          end)

        if status && headers do
          Mint.WebSocket.new(conn, ref, status, headers)
        else
          accept_upgrade(conn, ref)
        end
    after
      2000 -> flunk("websocket upgrade not completed")
    end
  end

  defp send_json(conn, websocket, ref, map) do
    {:ok, websocket, data} = Mint.WebSocket.encode(websocket, {:text, Jason.encode!(map)})
    {:ok, conn} = Mint.WebSocket.stream_request_body(conn, ref, data)
    {conn, websocket}
  end

  defp recv_text_frames(conn, websocket, ref, acc, timeout) do
    receive do
      message ->
        case Mint.WebSocket.stream(conn, message) do
          {:ok, conn, responses} ->
            {websocket, frames} = decode_frames(websocket, ref, responses)
            acc = acc ++ for({:text, t} <- frames, do: t)

            if Enum.any?(frames, &match?({:text, _}, &1)) and
                 Enum.any?(acc, fn t -> Jason.decode!(t)["is_final"] == true end) do
              acc
            else
              recv_text_frames(conn, websocket, ref, acc, timeout)
            end

          {:error, _conn, _reason, _responses} ->
            acc
        end
    after
      timeout -> acc
    end
  end

  defp decode_frames(websocket, ref, responses) do
    Enum.reduce(responses, {websocket, []}, fn
      {:data, ^ref, data}, {ws, frames} ->
        {:ok, ws, decoded} = Mint.WebSocket.decode(ws, data)
        {ws, frames ++ decoded}

      _other, acc ->
        acc
    end)
  end
end
