# ElevenLabs Elixir SDK — Speech Engine

**Date:** 2026-05-21
**Status:** Approved design, pending implementation plan

## Overview

A standalone Elixir library (`elevenlabs`, namespace `ElevenLabs`) that implements
the ElevenLabs **Speech Engine** feature, and only that feature. It is a focused
port of the `speech_engine` module from `elevenlabs-python`.

Speech Engine lets you build server-side voice agents. ElevenLabs streams
real-time user transcripts to *your* server over a WebSocket, and your code
streams LLM responses back for text-to-speech synthesis. Your server is the
WebSocket endpoint; ElevenLabs is the client that connects to it.

The library has two halves, both in scope (full parity):

1. **REST CRUD API** — manage Speech Engine resources (`list`, `create`, `get`,
   `update`, `delete`) against `v1/speech-engine`.
2. **WebSocket server runtime** — accept connections from ElevenLabs, verify
   them, run conversation sessions, stream agent responses, and handle
   interruption.

## Goals

- 1:1 behavioural parity with the Python `speech_engine` module's wire protocol,
  REST endpoints, and JWT verification.
- Idiomatic Elixir: `{:ok, _} / {:error, _}` tuples, a behaviour for handlers,
  the `WebSock` interface, OTP supervision, process-based concurrency.
- Embeddable in any Phoenix/Plug app *and* runnable standalone.

## Non-goals (YAGNI)

- **No LLM provider auto-detection.** Python auto-detects OpenAI/Anthropic/Gemini
  stream chunk shapes. Here, `send_response/2` accepts strings and
  Enumerables/Streams of binary text deltas only. Developers map their LLM
  client's stream to text.
- **No full modeling of nested config types.** The deeply nested config blobs
  (`asr`, `tts`, `turn`, `conversation`, `privacy`, `call_limits`, `overrides`,
  `metadata`) are passed and returned as plain maps, not ported structs.
- **No sync/async split.** Elixir is concurrent by default; there is one API.
- No other ElevenLabs features (TTS, voices, agents, etc.).

## Background: what we are porting

From `elevenlabs-python/src/elevenlabs/speech_engine/`:

- `client.py` / `raw_client.py` — REST CRUD over `v1/speech-engine`.
- `session.py` — per-connection WebSocket state machine, event emitter,
  interruption, streamed responses.
- `server.py` — standalone `websockets` server with per-connection JWT
  verification.
- `resource.py` — `verify_speech_engine_jwt`, the `SpeechEngineResource` handle
  (`serve`, `create_session`, `verify_request`).
- `types.py` — wire protocol constants, `ConversationMessage`, WebSocket
  abstraction.

### Wire protocol

Incoming (ElevenLabs → your server):

| Message | Shape |
|---|---|
| init | `{"type":"init","conversation_id":"..."}` |
| user_transcript | `{"type":"user_transcript","user_transcript":[{"role","content"}...],"event_id":N}` |
| ping | `{"type":"ping"}` |
| close | `{"type":"close"}` |
| error | `{"type":"error","message":"..."}` |

Outgoing (your server → ElevenLabs):

| Message | Shape |
|---|---|
| agent_response | `{"type":"agent_response","content":"...","event_id":N,"is_final":bool}` |
| pong | `{"type":"pong"}` |

Unknown incoming message types are ignored for forward compatibility.

### REST endpoints

| Op | Method + path | Returns |
|---|---|---|
| list | `GET v1/speech-engine` (params: page_size, search, sort_direction, sort_by, cursor) | `ListResponse` |
| create | `POST v1/speech-engine` | `Response` |
| get | `GET v1/speech-engine/{id}` | `Response` |
| update | `PATCH v1/speech-engine/{id}` | `Response` |
| delete | `DELETE v1/speech-engine/{id}` | `:ok` |

Base URL `https://api.elevenlabs.io`; auth header `xi-api-key`. `id` accepts
`seng_` or `agent_` prefixes (opaque to us).

### JWT verification

Incoming WebSocket connections carry header
`X-Elevenlabs-Speech-Engine-Authorization` with an HS256 JWT. Verification
(ported exactly):

- Strip an optional `Bearer ` prefix; split into 3 dot-separated parts.
- HMAC secret = `SHA-256(api_key)`.
- Expected signature = `HMAC-SHA256(secret, "<header_b64>.<payload_b64>")`,
  constant-time compared against the decoded signature part.
- Claims: `iss == "https://api.elevenlabs.io/convai/speech-engine"`,
  `sub == "convai_speech_engine_upstream"`, `exp` and `iat` present, checked with
  60s leeway.

## Architecture

### Approach (chosen)

The session is a `WebSock` callback module running in the connection process
(which owns the socket). Each `user_transcript` spawns the developer's handler
in a **supervised, cancellable Task**. The handler calls `send_response/2`,
which forwards text chunks back to the connection process as Erlang messages;
the connection process pushes them as WS frames, **gated by `event_id`** so that
chunks from a cancelled (interrupted) response are dropped. Interruption = kill
the Task, which also aborts any in-flight LLM request enumerating inside it.

Rejected alternatives: a GenServer-per-connection layer (the WebSock process is
already a process; pushing frames must still happen there — pure indirection);
running the handler inline in the connection process (cannot read the next frame
mid-response, so interruption can't be detected — breaks the headline feature).

### Module & file layout

```
mix.exs
README.md
.formatter.exs
.gitignore
lib/elevenlabs.ex                                  # ElevenLabs.new/1 -> %Client{}
lib/elevenlabs/client.ex                           # %Client{api_key, base_url, req}
lib/elevenlabs/error.ex                            # %Error{status, body, reason}
lib/elevenlabs/application.ex                      # starts ElevenLabs.TaskSupervisor
lib/elevenlabs/speech_engine.ex                    # REST CRUD + serve/2, stop/1, verify_request/2
lib/elevenlabs/speech_engine/config.ex             # %Config{ws_url, request_headers}
lib/elevenlabs/speech_engine/response.ex           # full SpeechEngineResponse
lib/elevenlabs/speech_engine/summary_response.ex   # list item
lib/elevenlabs/speech_engine/list_response.ex      # %ListResponse{speech_engines, next_cursor, has_more}
lib/elevenlabs/speech_engine/conversation_message.ex  # %ConversationMessage{role, content}
lib/elevenlabs/speech_engine/handler.ex            # @behaviour
lib/elevenlabs/speech_engine/jwt.ex                # verify/2
lib/elevenlabs/speech_engine/session.ex            # WebSock module + %Session{} handle + send_response/2
lib/elevenlabs/speech_engine/server.ex             # Bandit runner (child_spec/start_link)
lib/elevenlabs/speech_engine/plug.ex               # verify JWT -> upgrade to Session
test/...
```

## Public API surface

### Client + REST

```elixir
client = ElevenLabs.new(api_key: "sk_...")            # or ELEVENLABS_API_KEY env; base_url overridable

{:ok, %ListResponse{}}  = ElevenLabs.SpeechEngine.list(client, page_size: 30, search: "x",
                                                        sort_direction: :asc, sort_by: :name, cursor: nil)
{:ok, %Response{}}      = ElevenLabs.SpeechEngine.create(client,
                            speech_engine: %{ws_url: "wss://my.app/ws"}, name: "support bot",
                            asr: %{...}, tts: %{...}, language: "en", tags: ["x"])
{:ok, %Response{}}      = ElevenLabs.SpeechEngine.get(client, "seng_123")
{:ok, %Response{}}      = ElevenLabs.SpeechEngine.update(client, "seng_123", name: "renamed")
:ok                     = ElevenLabs.SpeechEngine.delete(client, "seng_123")
```

- `create` requires `speech_engine`; everything else optional. `speech_engine`
  accepts a `%Config{}` or a bare map. Nested config opts accept maps.
- Non-2xx → `{:error, %ElevenLabs.Error{status: integer, body: term}}`.
  Transport failures → `{:error, %ElevenLabs.Error{reason: term}}`.

### Handler behaviour

```elixir
defmodule MyAgent do
  @behaviour ElevenLabs.SpeechEngine.Handler
  alias ElevenLabs.SpeechEngine.Session

  @impl true
  def handle_transcript(transcript, session) do
    # transcript :: [%ConversationMessage{role, content}]
    Session.send_response(session, MyLLM.stream(transcript))
  end

  # all optional, default no-ops provided via `use`:
  @impl true
  def handle_init(_conversation_id, _session), do: :ok
  @impl true
  def handle_close(_session), do: :ok
  @impl true
  def handle_error(_error, _session), do: :ok
end
```

Callbacks:

| Callback | Signature | Runs in |
|---|---|---|
| `handle_init/2` | `(conversation_id :: String.t(), Session.t()) -> any` | connection process (keep quick) |
| `handle_transcript/2` | `([ConversationMessage.t()], Session.t()) -> any` | cancellable Task |
| `handle_close/1` | `(Session.t()) -> any` | connection process |
| `handle_error/2` | `(error :: term, Session.t()) -> any` | connection process |

`use ElevenLabs.SpeechEngine.Handler` provides overridable no-op defaults for all
but `handle_transcript/2`, which is required.

### Session handle + send_response

`%ElevenLabs.SpeechEngine.Session{}` is the handle passed to callbacks; it carries
the connection pid, the current `event_id`, and `conversation_id`.

```elixir
Session.send_response(session, "Hello world")          # single string
Session.send_response(session, stream_of_binaries)     # Enumerable/Stream of binaries
Session.conversation_id(session)                        # String.t() | nil
```

- String → one `agent_response` chunk (`is_final: false`) then a final empty one
  (`is_final: true`).
- Enumerable → each binary delta as a chunk, then the final marker.
- Called outside a transcript context (e.g. from `handle_init`, where `event_id`
  is nil) → logs a warning and is a no-op, matching Python.

### Standalone server / serve

```elixir
{:ok, pid} = ElevenLabs.SpeechEngine.serve(client, handler: MyAgent, port: 3001, path: "/ws", debug: true)
:ok = ElevenLabs.SpeechEngine.stop(pid)
```

`serve/2` starts `ElevenLabs.SpeechEngine.Server` (Bandit + the verify/upgrade
Plug) and returns `{:ok, pid}` — non-blocking and supervisable, unlike Python's
blocking `serve()`. `Server` also exposes `child_spec/1` for direct use in a
supervision tree. `api_key` is taken from the `client` (or passed explicitly).

### Embedding (Phoenix / Plug)

```elixir
# Plug.Router / Phoenix router
forward "/speech-engine/ws", to: ElevenLabs.SpeechEngine.Plug,
  init_opts: [api_key: System.fetch_env!("ELEVENLABS_API_KEY"), handler: MyAgent, debug: true]
```

`ElevenLabs.SpeechEngine.Plug` verifies the auth header (401 on failure; optional
`path` check → 404) then `WebSockAdapter.upgrade/4` to `Session`.
`ElevenLabs.SpeechEngine.verify_request(conn_or_headers, api_key) :: boolean` is
exposed for fully manual integration.

## Concurrency & interruption model (detailed)

Connection process state (the `WebSock` state): `handler`, `conversation_id`,
`current_task` (Task ref/pid or nil), `current_event_id`, `debug`. (No `api_key`:
JWT verification happens in the Plug before the upgrade, so the session never
needs it.)

- **`handle_in` `init`** → set `conversation_id`, call `handle_init/2` inline,
  `{:ok, state}`.
- **`handle_in` `user_transcript`**:
  - If `event_id == current_event_id` and the task is still alive → duplicate,
    skip.
  - Otherwise kill `current_task` if alive (interruption), parse transcript into
    `[%ConversationMessage{}]`, set `current_event_id`, and spawn
    `Task.Supervisor.async_nolink(ElevenLabs.TaskSupervisor, fn -> ... end)` that
    runs `handler.handle_transcript(transcript, %Session{conn: self, event_id:
    new_id, conversation_id: cid})`.
- **`handle_in` `ping`** → `{:push, {:text, pong}, state}`.
- **`handle_in` `close`** → `handle_close/1`, `{:stop, :normal, state}`.
- **`handle_in` `error`** → `handle_error/2`, `{:ok, state}`.
- **`handle_info` `{:se_chunk, event_id, content, is_final}`** (from a handler's
  `send_response`) → push the `agent_response` frame **only if `event_id ==
  current_event_id`**, else drop; `{:ok, state}` / `{:push, frame, state}`.
- **`handle_info` task `:DOWN`/result**:
  - normal completion → clear `current_task`.
  - killed (interruption) → ignore.
  - crash → `handle_error/2` + push final marker, keep the connection open.
- **`terminate/2`** → if not already closed, call `handle_close/1`.

`send_response/2` runs in the Task; it enumerates the response and `send/2`s one
message per chunk to the connection pid, then a final marker. Message ordering
per process guarantees in-order delivery. Killing the Task (`Process.exit(pid,
:kill)`) aborts the enumeration and any in-flight LLM HTTP request inside it; the
event-id gate discards any already-queued stale chunks.

## Dependencies (mix.exs)

Runtime: `req` (~> 0.5), `jason` (~> 1.4), `bandit` (~> 1.5), `websock_adapter`
(~> 0.5), `plug` (~> 1.16, for the Plug behaviour and `Plug.Crypto.secure_compare/2`).

Dev/test: `mint_web_socket` (end-to-end WS client in tests), `ex_doc`.

`ElevenLabs.Application` (declared via `mod:` in mix.exs) starts a single
`Task.Supervisor` named `ElevenLabs.TaskSupervisor`.

## Testing strategy

- **`jwt_test`** — valid token; bad signature; wrong `iss`/`sub`; expired (beyond
  leeway); `iat` in the future; malformed (not 3 parts); `Bearer ` prefix
  handling; leeway boundaries.
- **`session_test`** — drive `WebSock` callbacks directly (`init/1`,
  `handle_in/2`, `handle_info/2`, `terminate/2`): init sets conversation_id and
  fires `handle_init`; transcript dispatches to handler and pushes streamed
  chunks + final; new transcript cancels the prior task (interruption); duplicate
  event_id is skipped; ping → pong; close fires `handle_close` and stops; error
  fires `handle_error`; stale chunks are gated out; handler crash fires
  `handle_error` and keeps the socket.
- **`client_test`** — REST request shape (method, path, params, body, header) and
  response decoding into structs, via `Req.Test` stubs; error mapping for non-2xx.
- **`server_test`** — one real end-to-end: boot `Server`, connect with
  `Mint.WebSocket`, exercise the JWT handshake (accept valid, reject invalid) and
  a full `init` → `user_transcript` → streamed `agent_response` round trip.

## Open questions

None. Decisions locked: full parity; WebSock + Bandit; behaviour-based handlers;
strings/streams only for `send_response`; nested config as maps; `serve/2`
returns `{:ok, pid}`.
