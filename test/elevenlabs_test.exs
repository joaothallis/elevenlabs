defmodule ElevenLabsTest do
  use ExUnit.Case, async: true

  test "new/1 uses api_key opt, default base_url, and sets xi-api-key header" do
    client = ElevenLabs.new(api_key: "sk_123")
    assert %ElevenLabs.Client{api_key: "sk_123", base_url: "https://api.elevenlabs.io"} = client
    assert Req.Request.get_header(client.req, "xi-api-key") == ["sk_123"]
  end

  test "new/1 falls back to ELEVENLABS_API_KEY env" do
    System.put_env("ELEVENLABS_API_KEY", "sk_env")
    on_exit(fn -> System.delete_env("ELEVENLABS_API_KEY") end)
    assert %ElevenLabs.Client{api_key: "sk_env"} = ElevenLabs.new()
  end

  test "new/1 allows overriding base_url and merging req options" do
    client =
      ElevenLabs.new(api_key: "k", base_url: "http://localhost:9999", req_options: [retry: false])

    assert client.base_url == "http://localhost:9999"
    assert client.req.options[:retry] == false
  end
end
