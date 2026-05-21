defmodule ElevenLabs.SpeechEngine.ServerStartTest do
  use ExUnit.Case, async: false

  alias ElevenLabs.SpeechEngine

  defp free_port do
    {:ok, socket} = :gen_tcp.listen(0, [])
    {:ok, port} = :inet.port(socket)
    :gen_tcp.close(socket)
    port
  end

  test "serve/2 with an api key string starts a live server and stop/1 shuts it down" do
    port = free_port()

    assert {:ok, pid} =
             SpeechEngine.serve("sk_test", handler: ElevenLabs.RecordingHandler, port: port)

    assert Process.alive?(pid)
    assert :ok = SpeechEngine.stop(pid)
    refute Process.alive?(pid)
  end

  test "serve/2 accepts a Client and reads its api key" do
    port = free_port()
    client = ElevenLabs.new(api_key: "sk_from_client")

    assert {:ok, pid} =
             SpeechEngine.serve(client, handler: ElevenLabs.RecordingHandler, port: port)

    on_exit(fn -> if Process.alive?(pid), do: SpeechEngine.stop(pid) end)
    assert Process.alive?(pid)
  end
end
