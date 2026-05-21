# ElevenLabs Elixir SDK — Speech Engine

An Elixir SDK for the [ElevenLabs](https://elevenlabs.io/) **Speech Engine**:
manage speech engine resources over REST, and run the server-side voice-agent
WebSocket loop where ElevenLabs streams user transcripts to your server and you
stream LLM responses back for text-to-speech synthesis.

## Installation

```elixir
def deps do
  [{:elevenlabs, "~> 0.1"}]
end
```

## REST API

```elixir
client = ElevenLabs.new(api_key: System.fetch_env!("ELEVENLABS_API_KEY"))

{:ok, list} = ElevenLabs.SpeechEngine.list(client, page_size: 30)
{:ok, engine} = ElevenLabs.SpeechEngine.create(client, speech_engine: %{ws_url: "wss://my.app/ws"}, name: "support bot")
{:ok, engine} = ElevenLabs.SpeechEngine.get(client, "seng_123")
{:ok, engine} = ElevenLabs.SpeechEngine.update(client, "seng_123", name: "renamed")
:ok = ElevenLabs.SpeechEngine.delete(client, "seng_123")
```

## Defining a handler

```elixir
defmodule MyAgent do
  use ElevenLabs.SpeechEngine.Handler
  alias ElevenLabs.SpeechEngine.Session

  @impl true
  def handle_transcript(transcript, session) do
    # transcript is a list of %ElevenLabs.SpeechEngine.ConversationMessage{role, content}
    Session.send_response(session, MyLLM.stream(transcript))  # string or Stream of binaries
  end

  # optional: handle_init/2, handle_close/1, handle_error/2 (default no-ops)
end
```

When a new transcript arrives while a previous response is still streaming, the
previous handler task is cancelled automatically — any in-flight LLM request
running inside it is aborted.

## Standalone server

```elixir
{:ok, pid} = ElevenLabs.SpeechEngine.serve(client, handler: MyAgent, port: 3001)
# ...
:ok = ElevenLabs.SpeechEngine.stop(pid)
```

Or add it to your supervision tree:

```elixir
children = [
  {ElevenLabs.SpeechEngine.Server, api_key: api_key, handler: MyAgent, port: 3001}
]
```

## Embedding in Phoenix / Plug

```elixir
forward "/speech-engine/ws", to: ElevenLabs.SpeechEngine.Plug,
  init_opts: [api_key: api_key, handler: MyAgent]
```

The Plug verifies the `X-Elevenlabs-Speech-Engine-Authorization` JWT before
upgrading the connection.

## Development

This repository ships a [Nix flake](flake.nix). Running `nix develop` drops you
into a shell with Elixir and Erlang already on `PATH`. The full test suite runs
with:

```bash
nix develop --command mix test
```

## License

MIT
