# Speech Engine Elixir SDK Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a standalone Elixir library (`elevenlabs`) implementing only the ElevenLabs Speech Engine: REST CRUD over `v1/speech-engine` plus a WebSocket server runtime (sessions, streamed agent responses, interruption, JWT verification).

**Architecture:** The session is a `WebSock` callback module running in the connection process. Each `user_transcript` spawns the developer's handler in a supervised, cancellable Task; `send_response/2` forwards text chunks back to the connection process as messages, which pushes them as WS frames gated by `event_id`. Interruption = kill the Task. REST uses `Req`; standalone serving uses `Bandit` + a verify/upgrade `Plug`.

**Tech Stack:** Elixir, `req`, `jason`, `bandit`, `websock_adapter`, `plug`; tests with ExUnit, `Req.Test`, and `mint_web_socket`.

**Spec:** `docs/superpowers/specs/2026-05-21-speech-engine-elixir-design.md`

---

## Conventions for every commit step

- Run `mix format` before committing.
- End every commit message with this trailer (per the user's CLAUDE.md):
  `Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>`
- The user's git signs commits by default; if a GPG passphrase prompt times out, add `--no-gpg-sign`. Commit messages below omit the trailer for brevity — always append it.

---

## Task 1: Project scaffold & dependencies

**Files:**
- Create: `mix.exs`
- Create: `lib/elevenlabs/application.ex`
- Create: `.formatter.exs`
- Create: `.gitignore`
- Create: `test/test_helper.exs`

- [ ] **Step 1: Create `mix.exs`**

```elixir
defmodule ElevenLabs.MixProject do
  use Mix.Project

  def project do
    [
      app: :elevenlabs,
      version: "0.1.0",
      elixir: "~> 1.15",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      name: "ElevenLabs",
      description: "Elixir SDK for the ElevenLabs Speech Engine",
      package: package(),
      docs: [main: "readme", extras: ["README.md"]]
    ]
  end

  def application do
    [
      extra_applications: [:logger, :crypto],
      mod: {ElevenLabs.Application, []}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:req, "~> 0.5"},
      {:jason, "~> 1.4"},
      {:bandit, "~> 1.5"},
      {:websock_adapter, "~> 0.5"},
      {:plug, "~> 1.16"},
      {:mint_web_socket, "~> 1.0", only: :test},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
    ]
  end

  defp package do
    [licenses: ["MIT"], links: %{"GitHub" => "https://github.com/elevenlabs/elevenlabs-elixir"}]
  end
end
```

- [ ] **Step 2: Create `lib/elevenlabs/application.ex`**

```elixir
defmodule ElevenLabs.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Task.Supervisor, name: ElevenLabs.TaskSupervisor}
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: ElevenLabs.Supervisor)
  end
end
```

- [ ] **Step 3: Create `.formatter.exs`**

```elixir
[
  inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"]
]
```

- [ ] **Step 4: Create `.gitignore`**

```
/_build/
/cover/
/deps/
/doc/
/.fetch
erl_crash.dump
*.ez
*.beam
/config/*.secret.exs
.elixir_ls/
```

- [ ] **Step 5: Create `test/test_helper.exs`**

```elixir
ExUnit.start()
```

- [ ] **Step 6: Fetch deps and compile**

Run: `mix deps.get && mix compile`
Expected: deps resolve; compiles with no errors (warnings about unused modules are fine).

- [ ] **Step 7: Verify the app boots (Task.Supervisor starts)**

Run: `mix run -e "IO.inspect(Process.whereis(ElevenLabs.TaskSupervisor))"`
Expected: prints a non-nil PID.

- [ ] **Step 8: Commit**

```bash
git add mix.exs mix.lock lib/elevenlabs/application.ex .formatter.exs .gitignore test/test_helper.exs
git commit -m "chore: scaffold mix project with deps and Task.Supervisor"
```

---

## Task 2: Error struct + Client + `ElevenLabs.new/1`

**Files:**
- Create: `lib/elevenlabs/error.ex`
- Create: `lib/elevenlabs/client.ex`
- Create: `lib/elevenlabs.ex`
- Test: `test/elevenlabs_test.exs`

- [ ] **Step 1: Write the failing test**

```elixir
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
    client = ElevenLabs.new(api_key: "k", base_url: "http://localhost:9999", req_options: [retry: false])
    assert client.base_url == "http://localhost:9999"
    assert client.req.options[:retry] == false
  end
end
```

- [ ] **Step 2: Run it to verify it fails**

Run: `mix test test/elevenlabs_test.exs`
Expected: FAIL — `ElevenLabs.new/1` / `ElevenLabs.Client` undefined.

- [ ] **Step 3: Create `lib/elevenlabs/error.ex`**

```elixir
defmodule ElevenLabs.Error do
  @moduledoc """
  Represents a failed ElevenLabs API call.

  `status` and `body` are set for non-2xx HTTP responses; `reason` is set for
  transport-level failures (the underlying exception).
  """

  defexception [:status, :body, :reason]

  @type t :: %__MODULE__{status: pos_integer() | nil, body: term(), reason: term()}

  @impl true
  def message(%__MODULE__{status: status, body: body}) when not is_nil(status) do
    "ElevenLabs API error (status #{status}): #{inspect(body)}"
  end

  def message(%__MODULE__{reason: reason}) do
    "ElevenLabs request failed: #{inspect(reason)}"
  end
end
```

- [ ] **Step 4: Create `lib/elevenlabs/client.ex`**

```elixir
defmodule ElevenLabs.Client do
  @moduledoc """
  Holds configuration for talking to the ElevenLabs API: the API key, base URL,
  and a preconfigured `Req` request. Build one with `ElevenLabs.new/1`.
  """

  defstruct [:api_key, :base_url, :req]

  @type t :: %__MODULE__{
          api_key: String.t() | nil,
          base_url: String.t(),
          req: Req.Request.t()
        }
end
```

- [ ] **Step 5: Create `lib/elevenlabs.ex`**

```elixir
defmodule ElevenLabs do
  @moduledoc """
  Entry point for the ElevenLabs Speech Engine SDK.

  Build a client with `new/1`, then call the functions in
  `ElevenLabs.SpeechEngine`.
  """

  alias ElevenLabs.Client

  @default_base_url "https://api.elevenlabs.io"

  @doc """
  Builds an `ElevenLabs.Client`.

  Options:
    * `:api_key` — defaults to the `ELEVENLABS_API_KEY` environment variable.
    * `:base_url` — defaults to `#{@default_base_url}`.
    * `:req_options` — extra options merged into `Req.new/1` (useful for tests).
  """
  @spec new(keyword()) :: Client.t()
  def new(opts \\ []) do
    api_key = opts[:api_key] || System.get_env("ELEVENLABS_API_KEY")
    base_url = opts[:base_url] || @default_base_url
    req_options = Keyword.get(opts, :req_options, [])

    req =
      [base_url: base_url]
      |> Keyword.merge(req_options)
      |> Req.new()
      |> put_api_key(api_key)

    %Client{api_key: api_key, base_url: base_url, req: req}
  end

  defp put_api_key(req, nil), do: req
  defp put_api_key(req, key), do: Req.Request.put_header(req, "xi-api-key", key)
end
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `mix test test/elevenlabs_test.exs`
Expected: PASS (3 tests).

- [ ] **Step 7: Commit**

```bash
git add lib/elevenlabs.ex lib/elevenlabs/client.ex lib/elevenlabs/error.ex test/elevenlabs_test.exs
git commit -m "feat: add ElevenLabs.new/1, Client, and Error"
```

---

## Task 3: Speech Engine data types

**Files:**
- Create: `lib/elevenlabs/speech_engine/config.ex`
- Create: `lib/elevenlabs/speech_engine/conversation_message.ex`
- Create: `lib/elevenlabs/speech_engine/summary_response.ex`
- Create: `lib/elevenlabs/speech_engine/list_response.ex`
- Create: `lib/elevenlabs/speech_engine/response.ex`
- Test: `test/elevenlabs/speech_engine/types_test.exs`

- [ ] **Step 1: Write the failing test**

```elixir
defmodule ElevenLabs.SpeechEngine.TypesTest do
  use ExUnit.Case, async: true

  alias ElevenLabs.SpeechEngine.{Config, ConversationMessage, ListResponse, Response, SummaryResponse}

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
    assert %SummaryResponse{speech_engine_id: "seng_1", name: "A", created_at_unix_secs: 5, tags: ["t"]} =
             SummaryResponse.from_json(%{
               "speech_engine_id" => "seng_1",
               "name" => "A",
               "created_at_unix_secs" => 5,
               "tags" => ["t"]
             })
  end

  test "ListResponse.from_json/1 maps nested summaries" do
    assert %ListResponse{speech_engines: [%SummaryResponse{speech_engine_id: "seng_1"}], next_cursor: "c", has_more: true} =
             ListResponse.from_json(%{
               "speech_engines" => [%{"speech_engine_id" => "seng_1", "name" => "A", "created_at_unix_secs" => 1, "tags" => []}],
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
```

- [ ] **Step 2: Run it to verify it fails**

Run: `mix test test/elevenlabs/speech_engine/types_test.exs`
Expected: FAIL — modules undefined.

- [ ] **Step 3: Create `lib/elevenlabs/speech_engine/config.ex`**

```elixir
defmodule ElevenLabs.SpeechEngine.Config do
  @moduledoc "WebSocket connection settings for the upstream transcript server."

  defstruct [:ws_url, :request_headers]

  @type t :: %__MODULE__{ws_url: String.t(), request_headers: map() | nil}

  @doc "Builds a `Config` from a decoded JSON map (string keys)."
  @spec from_json(map()) :: t()
  def from_json(%{"ws_url" => ws_url} = map) do
    %__MODULE__{ws_url: ws_url, request_headers: map["request_headers"]}
  end

  @doc "Converts a `Config` (or bare map) into a JSON-encodable map, dropping nil fields."
  @spec to_map(t() | map()) :: map()
  def to_map(%__MODULE__{ws_url: ws_url, request_headers: nil}), do: %{ws_url: ws_url}
  def to_map(%__MODULE__{ws_url: ws_url, request_headers: rh}), do: %{ws_url: ws_url, request_headers: rh}
  def to_map(map) when is_map(map), do: map
end
```

- [ ] **Step 4: Create `lib/elevenlabs/speech_engine/conversation_message.ex`**

```elixir
defmodule ElevenLabs.SpeechEngine.ConversationMessage do
  @moduledoc "A single message in a speech engine conversation."

  defstruct [:role, :content]

  @type t :: %__MODULE__{role: String.t(), content: String.t()}

  @spec from_json(map()) :: t()
  def from_json(map) when is_map(map) do
    %__MODULE__{role: map["role"], content: map["content"]}
  end
end
```

- [ ] **Step 5: Create `lib/elevenlabs/speech_engine/summary_response.ex`**

```elixir
defmodule ElevenLabs.SpeechEngine.SummaryResponse do
  @moduledoc "A speech engine as returned in a list response."

  defstruct [:speech_engine_id, :name, :created_at_unix_secs, :tags]

  @type t :: %__MODULE__{
          speech_engine_id: String.t(),
          name: String.t(),
          created_at_unix_secs: integer(),
          tags: [String.t()]
        }

  @spec from_json(map()) :: t()
  def from_json(map) when is_map(map) do
    %__MODULE__{
      speech_engine_id: map["speech_engine_id"],
      name: map["name"],
      created_at_unix_secs: map["created_at_unix_secs"],
      tags: map["tags"]
    }
  end
end
```

- [ ] **Step 6: Create `lib/elevenlabs/speech_engine/list_response.ex`**

```elixir
defmodule ElevenLabs.SpeechEngine.ListResponse do
  @moduledoc "Paginated list of speech engines."

  alias ElevenLabs.SpeechEngine.SummaryResponse

  defstruct [:speech_engines, :next_cursor, :has_more]

  @type t :: %__MODULE__{
          speech_engines: [SummaryResponse.t()],
          next_cursor: String.t() | nil,
          has_more: boolean()
        }

  @spec from_json(map()) :: t()
  def from_json(map) when is_map(map) do
    %__MODULE__{
      speech_engines: Enum.map(map["speech_engines"] || [], &SummaryResponse.from_json/1),
      next_cursor: map["next_cursor"],
      has_more: map["has_more"]
    }
  end
end
```

- [ ] **Step 7: Create `lib/elevenlabs/speech_engine/response.ex`**

```elixir
defmodule ElevenLabs.SpeechEngine.Response do
  @moduledoc """
  A full speech engine resource. The nested config blobs (`asr`, `tts`, `turn`,
  `conversation`, `privacy`, `call_limits`, `overrides`, `metadata`) are kept as
  plain maps rather than typed structs.
  """

  alias ElevenLabs.SpeechEngine.Config

  defstruct [
    :speech_engine_id,
    :name,
    :speech_engine,
    :asr,
    :tts,
    :turn,
    :conversation,
    :privacy,
    :call_limits,
    :language,
    :tags,
    :overrides,
    :metadata
  ]

  @type t :: %__MODULE__{
          speech_engine_id: String.t(),
          name: String.t(),
          speech_engine: Config.t() | nil,
          asr: map() | nil,
          tts: map() | nil,
          turn: map() | nil,
          conversation: map() | nil,
          privacy: map() | nil,
          call_limits: map() | nil,
          language: String.t() | nil,
          tags: [String.t()] | nil,
          overrides: map() | nil,
          metadata: map() | nil
        }

  @spec from_json(map()) :: t()
  def from_json(map) when is_map(map) do
    %__MODULE__{
      speech_engine_id: map["speech_engine_id"],
      name: map["name"],
      speech_engine: map["speech_engine"] && Config.from_json(map["speech_engine"]),
      asr: map["asr"],
      tts: map["tts"],
      turn: map["turn"],
      conversation: map["conversation"],
      privacy: map["privacy"],
      call_limits: map["call_limits"],
      language: map["language"],
      tags: map["tags"],
      overrides: map["overrides"],
      metadata: map["metadata"]
    }
  end
end
```

- [ ] **Step 8: Run the tests to verify they pass**

Run: `mix test test/elevenlabs/speech_engine/types_test.exs`
Expected: PASS (5 tests).

- [ ] **Step 9: Commit**

```bash
git add lib/elevenlabs/speech_engine/*.ex test/elevenlabs/speech_engine/types_test.exs
git commit -m "feat: add Speech Engine data types"
```

---

## Task 4: REST — list / get / delete

**Files:**
- Create: `lib/elevenlabs/speech_engine.ex`
- Test: `test/elevenlabs/speech_engine/client_read_test.exs`

- [ ] **Step 1: Write the failing test**

```elixir
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
          %{"speech_engine_id" => "seng_1", "name" => "A", "created_at_unix_secs" => 1, "tags" => []}
        ],
        "next_cursor" => "c2",
        "has_more" => true
      })
    end)

    assert {:ok, %ListResponse{speech_engines: [%SummaryResponse{speech_engine_id: "seng_1"}], next_cursor: "c2", has_more: true}} =
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
```

- [ ] **Step 2: Run it to verify it fails**

Run: `mix test test/elevenlabs/speech_engine/client_read_test.exs`
Expected: FAIL — `ElevenLabs.SpeechEngine` undefined.

- [ ] **Step 3: Create `lib/elevenlabs/speech_engine.ex` with read/delete + helpers**

```elixir
defmodule ElevenLabs.SpeechEngine do
  @moduledoc """
  REST CRUD for Speech Engine resources, plus the WebSocket server runtime
  entry points (`serve/2`, `stop/1`, `verify_request/2`).
  """

  alias ElevenLabs.{Client, Error}
  alias ElevenLabs.SpeechEngine.{Config, ListResponse, Response}

  @base "v1/speech-engine"
  @list_params [:page_size, :search, :sort_direction, :sort_by, :cursor]
  @body_keys [
    :name,
    :speech_engine,
    :asr,
    :tts,
    :turn,
    :conversation,
    :privacy,
    :call_limits,
    :language,
    :tags,
    :overrides
  ]

  @doc "Lists speech engines. Options: #{inspect(@list_params)}."
  @spec list(Client.t(), keyword()) :: {:ok, ListResponse.t()} | {:error, Error.t()}
  def list(%Client{req: req}, opts \\ []) do
    params = Keyword.take(opts, @list_params)

    req
    |> Req.get(url: @base, params: params)
    |> decode(&ListResponse.from_json/1)
  end

  @doc "Fetches a single speech engine by id."
  @spec get(Client.t(), String.t()) :: {:ok, Response.t()} | {:error, Error.t()}
  def get(%Client{req: req}, id) do
    req
    |> Req.get(url: "#{@base}/#{id}")
    |> decode(&Response.from_json/1)
  end

  @doc "Deletes a speech engine by id."
  @spec delete(Client.t(), String.t()) :: :ok | {:error, Error.t()}
  def delete(%Client{req: req}, id) do
    case Req.delete(req, url: "#{@base}/#{id}") do
      {:ok, %{status: status}} when status in 200..299 -> :ok
      {:ok, %{status: status, body: body}} -> {:error, %Error{status: status, body: body}}
      {:error, reason} -> {:error, %Error{reason: reason}}
    end
  end

  # --- internal helpers (create/update added in the next task) ---

  defp decode({:ok, %{status: status, body: body}}, fun) when status in 200..299, do: {:ok, fun.(body)}
  defp decode({:ok, %{status: status, body: body}}, _fun), do: {:error, %Error{status: status, body: body}}
  defp decode({:error, reason}, _fun), do: {:error, %Error{reason: reason}}

  defp build_body(opts) do
    for key <- @body_keys, Keyword.has_key?(opts, key), into: %{} do
      {key, encode_value(key, Keyword.fetch!(opts, key))}
    end
  end

  defp encode_value(:speech_engine, value), do: Config.to_map(value)
  defp encode_value(_key, value), do: value
end
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `mix test test/elevenlabs/speech_engine/client_read_test.exs`
Expected: PASS (4 tests). (`build_body`/`encode_value` are unused for now — the `create`/`update` task uses them next; leave them in place.)

- [ ] **Step 5: Commit**

```bash
git add lib/elevenlabs/speech_engine.ex test/elevenlabs/speech_engine/client_read_test.exs
git commit -m "feat: add Speech Engine REST list/get/delete"
```

---

## Task 5: REST — create / update

**Files:**
- Modify: `lib/elevenlabs/speech_engine.ex` (add `create/2`, `update/3`)
- Test: `test/elevenlabs/speech_engine/client_write_test.exs`

- [ ] **Step 1: Write the failing test**

```elixir
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
             SpeechEngine.create(client(__MODULE__), speech_engine: %{ws_url: "wss://x"}, name: "Bot")
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
```

- [ ] **Step 2: Run it to verify it fails**

Run: `mix test test/elevenlabs/speech_engine/client_write_test.exs`
Expected: FAIL — `create/2` / `update/3` undefined.

- [ ] **Step 3: Add `create/2` and `update/3`**

Insert these two public functions in `lib/elevenlabs/speech_engine.ex` after `delete/2` (before the `# --- internal helpers` comment):

```elixir
  @doc """
  Creates a speech engine. Requires `:speech_engine` (a `Config` or bare map);
  other keys (#{inspect(@body_keys)}) are optional and only sent when present.
  """
  @spec create(Client.t(), keyword()) :: {:ok, Response.t()} | {:error, Error.t()}
  def create(%Client{req: req}, opts) do
    req
    |> Req.post(url: @base, json: build_body(opts))
    |> decode(&Response.from_json/1)
  end

  @doc "Partially updates a speech engine. Only the provided keys are sent."
  @spec update(Client.t(), String.t(), keyword()) :: {:ok, Response.t()} | {:error, Error.t()}
  def update(%Client{req: req}, id, opts) do
    req
    |> Req.patch(url: "#{@base}/#{id}", json: build_body(opts))
    |> decode(&Response.from_json/1)
  end
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `mix test test/elevenlabs/speech_engine/client_write_test.exs`
Expected: PASS (3 tests).

- [ ] **Step 5: Run the whole suite + format**

Run: `mix format && mix test`
Expected: all green.

- [ ] **Step 6: Commit**

```bash
git add lib/elevenlabs/speech_engine.ex test/elevenlabs/speech_engine/client_write_test.exs
git commit -m "feat: add Speech Engine REST create/update"
```

---

## Task 6: JWT verification + test support

**Files:**
- Create: `lib/elevenlabs/speech_engine/jwt.ex`
- Create: `test/support/jwt_helper.ex`
- Create: `test/support/test_support.ex`
- Test: `test/elevenlabs/speech_engine/jwt_test.exs`

- [ ] **Step 1: Create `test/support/jwt_helper.ex`**

```elixir
defmodule ElevenLabs.JWTHelper do
  @moduledoc false

  @issuer "https://api.elevenlabs.io/convai/speech-engine"
  @subject "convai_speech_engine_upstream"

  @doc "A valid claim set, valid for one hour from now."
  def valid_payload do
    now = System.system_time(:second)
    %{"iss" => @issuer, "sub" => @subject, "iat" => now, "exp" => now + 3600}
  end

  @doc "Signs `payload` into an HS256 JWT using the ElevenLabs scheme (secret = sha256(api_key))."
  def sign(payload, api_key) do
    header = b64(Jason.encode!(%{"alg" => "HS256", "typ" => "JWT"}))
    body = b64(Jason.encode!(payload))
    secret = :crypto.hash(:sha256, api_key)
    sig = b64(:crypto.mac(:hmac, :sha256, secret, header <> "." <> body))
    "#{header}.#{body}.#{sig}"
  end

  defp b64(data), do: Base.url_encode64(data, padding: false)
end
```

- [ ] **Step 2: Create `test/support/test_support.ex`**

```elixir
defmodule ElevenLabs.TestSupport do
  @moduledoc false

  @doc "Registers `pid` as the recipient for test-handler callback messages."
  def set_test_pid(pid), do: Application.put_env(:elevenlabs, :test_pid, pid)

  @doc "The pid that test handlers send callback notifications to."
  def test_pid, do: Application.get_env(:elevenlabs, :test_pid)

  @doc "Wraps a map as a `WebSock` text frame, as `handle_in/2` expects."
  def frame(map), do: {Jason.encode!(map), [opcode: :text]}
end
```

- [ ] **Step 3: Write the failing test**

```elixir
defmodule ElevenLabs.SpeechEngine.JWTTest do
  use ExUnit.Case, async: true

  alias ElevenLabs.SpeechEngine.JWT
  alias ElevenLabs.JWTHelper

  @api_key "sk_secret"

  test "accepts a valid token" do
    token = JWTHelper.sign(JWTHelper.valid_payload(), @api_key)
    assert {:ok, payload} = JWT.verify(token, @api_key)
    assert payload["sub"] == "convai_speech_engine_upstream"
  end

  test "strips a Bearer prefix" do
    token = "Bearer " <> JWTHelper.sign(JWTHelper.valid_payload(), @api_key)
    assert {:ok, _} = JWT.verify(token, @api_key)
  end

  test "rejects a signature signed with the wrong key" do
    token = JWTHelper.sign(JWTHelper.valid_payload(), "wrong_key")
    assert {:error, :signature_mismatch} = JWT.verify(token, @api_key)
  end

  test "rejects a wrong issuer" do
    payload = %{JWTHelper.valid_payload() | "iss" => "https://evil.example"}
    token = JWTHelper.sign(payload, @api_key)
    assert {:error, :bad_issuer} = JWT.verify(token, @api_key)
  end

  test "rejects a wrong subject" do
    payload = %{JWTHelper.valid_payload() | "sub" => "nope"}
    token = JWTHelper.sign(payload, @api_key)
    assert {:error, :bad_subject} = JWT.verify(token, @api_key)
  end

  test "rejects an expired token beyond leeway" do
    now = System.system_time(:second)
    payload = %{JWTHelper.valid_payload() | "iat" => now - 7200, "exp" => now - 120}
    token = JWTHelper.sign(payload, @api_key)
    assert {:error, :expired} = JWT.verify(token, @api_key)
  end

  test "rejects an iat in the future beyond leeway" do
    now = System.system_time(:second)
    payload = %{JWTHelper.valid_payload() | "iat" => now + 120, "exp" => now + 3600}
    token = JWTHelper.sign(payload, @api_key)
    assert {:error, :iat_in_future} = JWT.verify(token, @api_key)
  end

  test "rejects a malformed token" do
    assert {:error, _} = JWT.verify("not.a.jwt.token", @api_key)
    assert {:error, _} = JWT.verify("onlyonepart", @api_key)
  end
end
```

- [ ] **Step 4: Run it to verify it fails**

Run: `mix test test/elevenlabs/speech_engine/jwt_test.exs`
Expected: FAIL — `JWT.verify/2` undefined.

- [ ] **Step 5: Create `lib/elevenlabs/speech_engine/jwt.ex`**

```elixir
defmodule ElevenLabs.SpeechEngine.JWT do
  @moduledoc """
  Verifies the HS256 JWT that ElevenLabs sends in the
  `X-Elevenlabs-Speech-Engine-Authorization` header. The HMAC secret is the
  SHA-256 hash of the API key.
  """

  @issuer "https://api.elevenlabs.io/convai/speech-engine"
  @subject "convai_speech_engine_upstream"
  @leeway 60

  @doc """
  Verifies `value` (a token, optionally `Bearer `-prefixed) against `api_key`.
  Returns `{:ok, payload}` or `{:error, reason}`.
  """
  @spec verify(String.t(), String.t()) :: {:ok, map()} | {:error, atom()}
  def verify(value, api_key) do
    token = value |> String.trim() |> strip_bearer()

    with [header, body, signature] <- String.split(token, "."),
         {:ok, payload_json} <- Base.url_decode64(body, padding: false),
         {:ok, payload} when is_map(payload) <- Jason.decode(payload_json),
         {:ok, signature_bytes} <- Base.url_decode64(signature, padding: false),
         :ok <- verify_signature(header, body, signature_bytes, api_key),
         :ok <- check_claims(payload) do
      {:ok, payload}
    else
      {:error, reason} when is_atom(reason) -> {:error, reason}
      _ -> {:error, :invalid}
    end
  end

  defp strip_bearer(token) do
    case String.split(token, " ", parts: 2) do
      [scheme, rest] -> if String.downcase(scheme) == "bearer", do: String.trim(rest), else: token
      _ -> token
    end
  end

  defp verify_signature(header, body, signature_bytes, api_key) do
    secret = :crypto.hash(:sha256, String.trim(api_key))
    expected = :crypto.mac(:hmac, :sha256, secret, header <> "." <> body)

    if Plug.Crypto.secure_compare(expected, signature_bytes) do
      :ok
    else
      {:error, :signature_mismatch}
    end
  end

  defp check_claims(payload) do
    now = System.system_time(:second)

    cond do
      payload["iss"] != @issuer -> {:error, :bad_issuer}
      payload["sub"] != @subject -> {:error, :bad_subject}
      not is_number(payload["exp"]) -> {:error, :missing_exp}
      not is_number(payload["iat"]) -> {:error, :missing_iat}
      payload["exp"] + @leeway < now -> {:error, :expired}
      payload["iat"] - @leeway > now -> {:error, :iat_in_future}
      true -> :ok
    end
  end
end
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `mix test test/elevenlabs/speech_engine/jwt_test.exs`
Expected: PASS (8 tests).

- [ ] **Step 7: Commit**

```bash
git add lib/elevenlabs/speech_engine/jwt.ex test/support/jwt_helper.ex test/support/test_support.ex test/elevenlabs/speech_engine/jwt_test.exs
git commit -m "feat: add Speech Engine JWT verification"
```

---

## Task 7: Handler behaviour

**Files:**
- Create: `lib/elevenlabs/speech_engine/handler.ex`
- Test: `test/elevenlabs/speech_engine/handler_test.exs`

- [ ] **Step 1: Write the failing test**

```elixir
defmodule ElevenLabs.SpeechEngine.HandlerTest do
  use ExUnit.Case, async: true

  defmodule Minimal do
    use ElevenLabs.SpeechEngine.Handler

    @impl true
    def handle_transcript(_transcript, _session), do: :handled
  end

  test "use provides overridable no-op defaults for the optional callbacks" do
    assert Minimal.handle_init("c1", :session) == :ok
    assert Minimal.handle_close(:session) == :ok
    assert Minimal.handle_error(:boom, :session) == :ok
  end

  test "the required callback is the one the module defines" do
    assert Minimal.handle_transcript([], :session) == :handled
  end

  test "the module declares the behaviour" do
    behaviours = Minimal.module_info(:attributes) |> Keyword.get_values(:behaviour) |> List.flatten()
    assert ElevenLabs.SpeechEngine.Handler in behaviours
  end
end
```

- [ ] **Step 2: Run it to verify it fails**

Run: `mix test test/elevenlabs/speech_engine/handler_test.exs`
Expected: FAIL — `ElevenLabs.SpeechEngine.Handler` undefined.

- [ ] **Step 3: Create `lib/elevenlabs/speech_engine/handler.ex`**

```elixir
defmodule ElevenLabs.SpeechEngine.Handler do
  @moduledoc """
  Behaviour for Speech Engine conversation handlers.

  Only `c:handle_transcript/2` is required. `use ElevenLabs.SpeechEngine.Handler`
  injects overridable no-op defaults for the other three callbacks.

      defmodule MyAgent do
        use ElevenLabs.SpeechEngine.Handler
        alias ElevenLabs.SpeechEngine.Session

        @impl true
        def handle_transcript(transcript, session) do
          Session.send_response(session, MyLLM.stream(transcript))
        end
      end
  """

  alias ElevenLabs.SpeechEngine.{ConversationMessage, Session}

  @doc "Called once when the conversation starts. Runs in the connection process — keep it quick."
  @callback handle_init(conversation_id :: String.t(), session :: Session.t()) :: any()

  @doc "Called for each user transcript. Runs in a cancellable Task; call `Session.send_response/2` here."
  @callback handle_transcript(transcript :: [ConversationMessage.t()], session :: Session.t()) :: any()

  @doc "Called when the conversation ends or the socket disconnects."
  @callback handle_close(session :: Session.t()) :: any()

  @doc "Called on a protocol error or when a transcript handler crashes."
  @callback handle_error(error :: term(), session :: Session.t()) :: any()

  @optional_callbacks handle_init: 2, handle_close: 1, handle_error: 2

  defmacro __using__(_opts) do
    quote do
      @behaviour ElevenLabs.SpeechEngine.Handler

      @impl true
      def handle_init(_conversation_id, _session), do: :ok

      @impl true
      def handle_close(_session), do: :ok

      @impl true
      def handle_error(_error, _session), do: :ok

      defoverridable handle_init: 2, handle_close: 1, handle_error: 2
    end
  end
end
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `mix test test/elevenlabs/speech_engine/handler_test.exs`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/elevenlabs/speech_engine/handler.ex test/elevenlabs/speech_engine/handler_test.exs
git commit -m "feat: add Speech Engine Handler behaviour"
```

---

## Task 8: Session struct + `send_response/2`

**Files:**
- Create: `lib/elevenlabs/speech_engine/session.ex` (struct + `send_response/2` + `conversation_id/1` only; WebSock callbacks come in later tasks)
- Test: `test/elevenlabs/speech_engine/session_send_test.exs`

- [ ] **Step 1: Write the failing test**

```elixir
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
```

- [ ] **Step 2: Run it to verify it fails**

Run: `mix test test/elevenlabs/speech_engine/session_send_test.exs`
Expected: FAIL — `Session` undefined.

- [ ] **Step 3: Create `lib/elevenlabs/speech_engine/session.ex`**

```elixir
defmodule ElevenLabs.SpeechEngine.Session do
  @moduledoc """
  A Speech Engine conversation session.

  This module is both the `WebSock` callback module (one instance per
  connection) and the `%Session{}` handle passed to `ElevenLabs.SpeechEngine.Handler`
  callbacks. Handlers call `send_response/2` to stream an agent reply back for
  TTS synthesis.
  """

  require Logger

  defstruct [:conn, :event_id, :conversation_id]

  @type t :: %__MODULE__{
          conn: pid(),
          event_id: integer() | nil,
          conversation_id: String.t() | nil
        }

  @doc "The conversation id assigned by the API (available once `handle_init` has fired)."
  @spec conversation_id(t()) :: String.t() | nil
  def conversation_id(%__MODULE__{conversation_id: id}), do: id

  @doc """
  Sends an agent response back for TTS synthesis. Accepts a binary or an
  Enumerable/Stream of binary text deltas. Must be called from within a
  transcript handler; called elsewhere it logs a warning and is a no-op.
  """
  @spec send_response(t(), binary() | Enumerable.t()) :: :ok
  def send_response(%__MODULE__{event_id: nil}, _response) do
    Logger.warning(
      "send_response/2 called outside of a transcript handler; ignoring. Responses " <>
        "can only be sent in reply to a user transcript."
    )

    :ok
  end

  def send_response(%__MODULE__{conn: conn, event_id: event_id}, response) when is_binary(response) do
    send(conn, {:se_chunk, event_id, response, false})
    send(conn, {:se_chunk, event_id, "", true})
    :ok
  end

  def send_response(%__MODULE__{conn: conn, event_id: event_id}, response) do
    Enum.each(response, fn
      delta when is_binary(delta) and delta != "" -> send(conn, {:se_chunk, event_id, delta, false})
      _ -> :ok
    end)

    send(conn, {:se_chunk, event_id, "", true})
    :ok
  end
end
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `mix test test/elevenlabs/speech_engine/session_send_test.exs`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/elevenlabs/speech_engine/session.ex test/elevenlabs/speech_engine/session_send_test.exs
git commit -m "feat: add Session struct and send_response/2"
```

---

## Task 9: Session WebSock — init + lifecycle messages + terminate

**Files:**
- Modify: `lib/elevenlabs/speech_engine/session.ex` (add `WebSock` callbacks: `init/1`, `handle_in/2` for init/ping/close/error/unknown, `terminate/2`, and a `call_handler` helper)
- Create: `test/support/recording_handler.ex`
- Test: `test/elevenlabs/speech_engine/session_lifecycle_test.exs`

- [ ] **Step 1: Create `test/support/recording_handler.ex`**

```elixir
defmodule ElevenLabs.RecordingHandler do
  @moduledoc false
  use ElevenLabs.SpeechEngine.Handler

  alias ElevenLabs.TestSupport

  @impl true
  def handle_init(conversation_id, _session) do
    send(TestSupport.test_pid(), {:handle_init, conversation_id})
  end

  @impl true
  def handle_close(_session) do
    send(TestSupport.test_pid(), :handle_close)
  end

  @impl true
  def handle_error(error, _session) do
    send(TestSupport.test_pid(), {:handle_error, error})
  end

  # Sends {:start, event_id}, sleeps, then {:done, event_id}. Used to test interruption.
  @impl true
  def handle_transcript(_transcript, session) do
    send(TestSupport.test_pid(), {:start, session.event_id})
    Process.sleep(300)
    send(TestSupport.test_pid(), {:done, session.event_id})
  end
end
```

- [ ] **Step 2: Write the failing test**

```elixir
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
    assert {:ok, new_state} = Session.handle_in(frame(%{type: "init", conversation_id: "conv_1"}), state)
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
```

- [ ] **Step 3: Run it to verify it fails**

Run: `mix test test/elevenlabs/speech_engine/session_lifecycle_test.exs`
Expected: FAIL — `Session.init/1` undefined.

- [ ] **Step 4: Add the WebSock lifecycle callbacks to `session.ex`**

Add `@behaviour WebSock` near the top of the module (just under `require Logger`):

```elixir
  @behaviour WebSock
```

Then append these callbacks and helpers inside the module (after `send_response/2`):

```elixir
  # ------------------------------------------------------------------
  # WebSock callbacks
  # ------------------------------------------------------------------

  @impl WebSock
  def init(opts) when is_map(opts) do
    state = %{
      handler: Map.fetch!(opts, :handler),
      debug: Map.get(opts, :debug, false),
      conversation_id: nil,
      current_task: nil,
      current_event_id: nil
    }

    {:ok, state}
  end

  @impl WebSock
  def handle_in({data, [opcode: opcode]}, state) when opcode in [:text, :binary] do
    case Jason.decode(data) do
      {:ok, msg} when is_map(msg) -> handle_message(msg, state)
      _ -> {:ok, state}
    end
  end

  @impl WebSock
  def terminate(_reason, state) do
    cancel_current(state)
    call_handler(state, :handle_close, [])
    :ok
  end

  # ------------------------------------------------------------------
  # Incoming message dispatch
  # ------------------------------------------------------------------

  defp handle_message(%{"type" => "init"} = msg, state) do
    conversation_id = msg["conversation_id"]
    state = %{state | conversation_id: conversation_id}
    call_handler(state, :handle_init, [conversation_id])
    {:ok, state}
  end

  defp handle_message(%{"type" => "ping"}, state) do
    {:push, {:text, Jason.encode!(%{type: "pong"})}, state}
  end

  defp handle_message(%{"type" => "close"}, state) do
    {:stop, :normal, state}
  end

  defp handle_message(%{"type" => "error"} = msg, state) do
    call_handler(state, :handle_error, [{:remote_error, msg["message"]}])
    {:ok, state}
  end

  defp handle_message(_unknown, state) do
    {:ok, state}
  end

  # ------------------------------------------------------------------
  # Internals
  # ------------------------------------------------------------------

  # Builds a Session handle (event_id nil for lifecycle callbacks) and invokes a
  # handler callback inline. Errors in lifecycle callbacks are logged, not fatal.
  defp call_handler(state, fun, args) do
    session = %__MODULE__{conn: self(), event_id: nil, conversation_id: state.conversation_id}
    apply(state.handler, fun, args ++ [session])
    :ok
  rescue
    error ->
      Logger.error("Speech Engine #{fun} handler raised: #{Exception.message(error)}")
      :ok
  end

  defp cancel_current(%{current_task: nil} = state), do: state

  defp cancel_current(%{current_task: task} = state) do
    Task.shutdown(task, :brutal_kill)
    %{state | current_task: nil}
  end
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `mix test test/elevenlabs/speech_engine/session_lifecycle_test.exs`
Expected: PASS (8 tests).

- [ ] **Step 6: Commit**

```bash
git add lib/elevenlabs/speech_engine/session.ex test/support/recording_handler.ex test/elevenlabs/speech_engine/session_lifecycle_test.exs
git commit -m "feat: add Session WebSock init, lifecycle dispatch, terminate"
```

---

## Task 10: Session WebSock — transcript dispatch + chunk push + event-id gating

**Files:**
- Modify: `lib/elevenlabs/speech_engine/session.ex` (add `user_transcript` handling, `handle_info/2` for `:se_chunk`, and transcript parsing)
- Create: `test/support/responder_handler.ex`
- Test: `test/elevenlabs/speech_engine/session_transcript_test.exs`

- [ ] **Step 1: Create `test/support/responder_handler.ex`**

```elixir
defmodule ElevenLabs.ResponderHandler do
  @moduledoc false
  use ElevenLabs.SpeechEngine.Handler

  alias ElevenLabs.SpeechEngine.Session
  alias ElevenLabs.TestSupport

  @impl true
  def handle_transcript(transcript, session) do
    send(TestSupport.test_pid(), {:got_transcript, transcript})
    Session.send_response(session, ["Hel", "lo"])
  end
end
```

- [ ] **Step 2: Write the failing test**

```elixir
defmodule ElevenLabs.SpeechEngine.SessionTranscriptTest do
  use ExUnit.Case, async: false

  alias ElevenLabs.SpeechEngine.{ConversationMessage, Session}
  alias ElevenLabs.TestSupport
  import ElevenLabs.TestSupport, only: [frame: 1]

  setup do
    TestSupport.set_test_pid(self())
    {:ok, state} = Session.init(%{handler: ElevenLabs.ResponderHandler})
    %{state: state}
  end

  test "user_transcript parses messages, spawns the handler, and tracks event_id", %{state: state} do
    msg = %{type: "user_transcript", event_id: 5, user_transcript: [%{role: "user", content: "hi"}]}
    assert {:ok, new_state} = Session.handle_in(frame(msg), state)

    assert new_state.current_event_id == 5
    assert new_state.current_task != nil

    assert_receive {:got_transcript, [%ConversationMessage{role: "user", content: "hi"}]}
    # send_response chunks are delivered to the connection process (here, the test process)
    assert_receive {:se_chunk, 5, "Hel", false}
    assert_receive {:se_chunk, 5, "lo", false}
    assert_receive {:se_chunk, 5, "", true}
  end

  test "handle_info pushes an agent_response frame for the current event_id", %{state: state} do
    state = %{state | current_event_id: 7}

    assert {:push, {:text, json}, ^state} = Session.handle_info({:se_chunk, 7, "hi", false}, state)

    assert Jason.decode!(json) == %{
             "type" => "agent_response",
             "content" => "hi",
             "event_id" => 7,
             "is_final" => false
           }
  end

  test "handle_info drops chunks whose event_id is stale", %{state: state} do
    state = %{state | current_event_id: 7}
    assert {:ok, ^state} = Session.handle_info({:se_chunk, 6, "stale", false}, state)
  end
end
```

- [ ] **Step 3: Run it to verify it fails**

Run: `mix test test/elevenlabs/speech_engine/session_transcript_test.exs`
Expected: FAIL — no `user_transcript` clause / `handle_info/2` undefined.

- [ ] **Step 4: Add transcript handling and chunk push**

Add a `user_transcript` clause to `handle_message/2` (place it before the `defp handle_message(_unknown, ...)` catch-all):

```elixir
  defp handle_message(%{"type" => "user_transcript"} = msg, state) do
    incoming = msg["event_id"]

    if duplicate?(incoming, state) do
      {:ok, state}
    else
      state = cancel_current(state)
      transcript = parse_transcript(msg["user_transcript"] || [])
      session = %__MODULE__{conn: self(), event_id: incoming, conversation_id: state.conversation_id}

      task =
        Task.Supervisor.async_nolink(ElevenLabs.TaskSupervisor, fn ->
          state.handler.handle_transcript(transcript, session)
        end)

      {:ok, %{state | current_task: task, current_event_id: incoming}}
    end
  end
```

Add the `handle_info/2` callback (place it with the other `@impl WebSock` callbacks, e.g. after `handle_in/2`):

```elixir
  @impl WebSock
  def handle_info({:se_chunk, event_id, content, is_final}, %{current_event_id: current} = state) do
    if event_id == current do
      frame = Jason.encode!(%{type: "agent_response", content: content, event_id: event_id, is_final: is_final})
      {:push, {:text, frame}, state}
    else
      {:ok, state}
    end
  end

  def handle_info(_msg, state), do: {:ok, state}
```

Add the transcript-parsing and duplicate helpers (next to `cancel_current/1`):

```elixir
  defp duplicate?(incoming, %{current_event_id: current, current_task: task}) do
    incoming != nil and incoming == current and task != nil and Process.alive?(task.pid)
  end

  defp parse_transcript(list) do
    Enum.map(list, fn msg ->
      %ElevenLabs.SpeechEngine.ConversationMessage{role: msg["role"], content: msg["content"]}
    end)
  end
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `mix test test/elevenlabs/speech_engine/session_transcript_test.exs`
Expected: PASS (3 tests).

- [ ] **Step 6: Commit**

```bash
git add lib/elevenlabs/speech_engine/session.ex test/support/responder_handler.ex test/elevenlabs/speech_engine/session_transcript_test.exs
git commit -m "feat: add transcript dispatch and gated agent_response push"
```

---

## Task 11: Session WebSock — task completion & crash handling

**Files:**
- Modify: `lib/elevenlabs/speech_engine/session.ex` (add `handle_info/2` clauses for the task result tuple and `:DOWN`)
- Create: `test/support/crash_handler.ex`
- Test: `test/elevenlabs/speech_engine/session_task_test.exs`

- [ ] **Step 1: Create `test/support/crash_handler.ex`**

```elixir
defmodule ElevenLabs.CrashHandler do
  @moduledoc false
  use ElevenLabs.SpeechEngine.Handler

  @impl true
  def handle_transcript(_transcript, _session) do
    raise "boom"
  end
end
```

- [ ] **Step 2: Write the failing test**

```elixir
defmodule ElevenLabs.SpeechEngine.SessionTaskTest do
  use ExUnit.Case, async: false

  alias ElevenLabs.SpeechEngine.Session
  alias ElevenLabs.TestSupport
  import ElevenLabs.TestSupport, only: [frame: 1]

  test "a normal task result clears current_task" do
    TestSupport.set_test_pid(self())
    {:ok, state} = Session.init(%{handler: ElevenLabs.ResponderHandler})

    msg = %{type: "user_transcript", event_id: 1, user_transcript: [%{role: "user", content: "hi"}]}
    {:ok, state} = Session.handle_in(frame(msg), state)
    task = state.current_task

    # the async_nolink task sends {ref, result} when it finishes
    assert_receive {ref, _result} when ref == task.ref, 1000
    assert {:ok, cleared} = Session.handle_info({task.ref, :done}, state)
    assert cleared.current_task == nil
  end

  test "a crashed task triggers handle_error and pushes a final marker" do
    TestSupport.set_test_pid(self())
    {:ok, state} = Session.init(%{handler: ElevenLabs.CrashHandler})
    state = %{state | conversation_id: "c1"}

    msg = %{type: "user_transcript", event_id: 4, user_transcript: [%{role: "user", content: "hi"}]}
    {:ok, state} = Session.handle_in(frame(msg), state)
    task = state.current_task

    assert_receive {:DOWN, ref, :process, _pid, reason} when ref == task.ref, 1000
    refute reason == :normal

    assert {:push, {:text, json}, cleared} =
             Session.handle_info({:DOWN, task.ref, :process, task.pid, reason}, state)

    assert cleared.current_task == nil
    decoded = Jason.decode!(json)
    assert decoded["type"] == "agent_response"
    assert decoded["is_final"] == true
    assert decoded["event_id"] == 4
    assert_receive {:handle_error, {:handler_crashed, _}}
  end
end
```

- [ ] **Step 3: Run it to verify it fails**

Run: `mix test test/elevenlabs/speech_engine/session_task_test.exs`
Expected: FAIL — the `:DOWN`/task-result messages fall through to the catch-all `handle_info/2` (no `handle_error`, no final marker), so assertions fail.

- [ ] **Step 4: Add task lifecycle clauses to `handle_info/2`**

Insert these clauses **before** the existing `def handle_info(_msg, state), do: {:ok, state}` catch-all:

```elixir
  # The async_nolink task finished normally; flush its pending :DOWN and clear it.
  def handle_info({ref, _result}, %{current_task: %Task{ref: ref}} = state) when is_reference(ref) do
    Process.demonitor(ref, [:flush])
    {:ok, %{state | current_task: nil}}
  end

  # The current transcript task went down. :normal/:killed are expected (completion
  # or interruption); anything else is a crash -> notify and close out the response.
  def handle_info({:DOWN, ref, :process, _pid, reason}, %{current_task: %Task{ref: ref}} = state) do
    state = %{state | current_task: nil}

    if reason in [:normal, :killed] do
      {:ok, state}
    else
      call_handler(state, :handle_error, [{:handler_crashed, reason}])

      frame =
        Jason.encode!(%{
          type: "agent_response",
          content: "",
          event_id: state.current_event_id,
          is_final: true
        })

      {:push, {:text, frame}, state}
    end
  end

  # Stale task messages from an already-cleared task — ignore.
  def handle_info({ref, _result}, state) when is_reference(ref), do: {:ok, state}
  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) when is_reference(ref), do: {:ok, state}
```

Also ensure `alias Task` is not needed — `Task` is a built-in; `%Task{ref: ref}` matches directly.

- [ ] **Step 5: Run the tests to verify they pass**

Run: `mix test test/elevenlabs/speech_engine/session_task_test.exs`
Expected: PASS (2 tests).

- [ ] **Step 6: Commit**

```bash
git add lib/elevenlabs/speech_engine/session.ex test/support/crash_handler.ex test/elevenlabs/speech_engine/session_task_test.exs
git commit -m "feat: handle transcript task completion and crashes"
```

---

## Task 12: Session WebSock — interruption & duplicate skip

**Files:**
- Test only: `test/elevenlabs/speech_engine/session_interruption_test.exs` (behaviour already implemented via `cancel_current/1` + `duplicate?/2`; this task proves it end-to-end)

- [ ] **Step 1: Write the failing test**

```elixir
defmodule ElevenLabs.SpeechEngine.SessionInterruptionTest do
  use ExUnit.Case, async: false

  alias ElevenLabs.SpeechEngine.Session
  alias ElevenLabs.TestSupport
  import ElevenLabs.TestSupport, only: [frame: 1]

  setup do
    TestSupport.set_test_pid(self())
    # RecordingHandler.handle_transcript sends {:start, id}, sleeps 300ms, then {:done, id}.
    {:ok, state} = Session.init(%{handler: ElevenLabs.RecordingHandler})
    %{state: state}
  end

  defp transcript(event_id) do
    frame(%{type: "user_transcript", event_id: event_id, user_transcript: [%{role: "user", content: "hi"}]})
  end

  test "a new transcript cancels the in-flight handler", %{state: state} do
    {:ok, state} = Session.handle_in(transcript(1), state)
    assert_receive {:start, 1}, 500

    # interrupt before the first handler finishes its 300ms sleep
    {:ok, state} = Session.handle_in(transcript(2), state)
    assert_receive {:start, 2}, 500

    assert state.current_event_id == 2
    refute_receive {:done, 1}, 600
    assert_receive {:done, 2}, 1000
  end

  test "a duplicate transcript (same event_id, task alive) is skipped", %{state: state} do
    {:ok, state} = Session.handle_in(transcript(1), state)
    assert_receive {:start, 1}, 500
    first_task = state.current_task

    {:ok, state} = Session.handle_in(transcript(1), state)
    # same task kept, handler not started again
    assert state.current_task == first_task
    refute_receive {:start, 1}, 200
  end
end
```

- [ ] **Step 2: Run it to verify it passes (behaviour already implemented)**

Run: `mix test test/elevenlabs/speech_engine/session_interruption_test.exs`
Expected: PASS (2 tests). If the duplicate test fails because the first task already finished (>300ms elapsed), it confirms `duplicate?/2` correctly only skips while the task is alive — but it should pass because the second `handle_in` runs immediately after `assert_receive {:start, 1}`.

- [ ] **Step 3: Commit**

```bash
git add test/elevenlabs/speech_engine/session_interruption_test.exs
git commit -m "test: cover interruption and duplicate-transcript skipping"
```

---

## Task 13: JWT-verifying Plug + `verify_request/2`

**Files:**
- Create: `lib/elevenlabs/speech_engine/plug.ex`
- Modify: `lib/elevenlabs/speech_engine.ex` (add `verify_request/2`)
- Test: `test/elevenlabs/speech_engine/plug_test.exs`

- [ ] **Step 1: Write the failing test**

```elixir
defmodule ElevenLabs.SpeechEngine.PlugTest do
  use ExUnit.Case, async: true
  import Plug.Test
  import Plug.Conn

  alias ElevenLabs.SpeechEngine
  alias ElevenLabs.SpeechEngine.Plug, as: SEPlug
  alias ElevenLabs.JWTHelper

  @api_key "sk_plug"
  @header "x-elevenlabs-speech-engine-authorization"

  defp opts(extra \\ []) do
    SEPlug.init(Keyword.merge([api_key: @api_key, handler: ElevenLabs.RecordingHandler], extra))
  end

  test "missing auth header -> 401" do
    conn = conn(:get, "/") |> SEPlug.call(opts())
    assert conn.status == 401
    assert conn.halted
  end

  test "invalid token -> 401" do
    conn =
      conn(:get, "/")
      |> put_req_header(@header, "Bearer nope")
      |> SEPlug.call(opts())

    assert conn.status == 401
  end

  test "path mismatch -> 404" do
    token = JWTHelper.sign(JWTHelper.valid_payload(), @api_key)

    conn =
      conn(:get, "/wrong")
      |> put_req_header(@header, token)
      |> SEPlug.call(opts(path: "/ws"))

    assert conn.status == 404
  end

  test "valid token -> connection is upgraded" do
    token = JWTHelper.sign(JWTHelper.valid_payload(), @api_key)

    conn =
      conn(:get, "/")
      |> put_req_header(@header, token)
      |> SEPlug.call(opts())

    assert conn.state == :upgraded
  end

  test "verify_request/2 accepts a conn with a valid token" do
    token = JWTHelper.sign(JWTHelper.valid_payload(), @api_key)
    conn = conn(:get, "/") |> put_req_header(@header, token)
    assert SpeechEngine.verify_request(conn, @api_key) == true
    assert SpeechEngine.verify_request(conn(:get, "/"), @api_key) == false
  end
end
```

- [ ] **Step 2: Run it to verify it fails**

Run: `mix test test/elevenlabs/speech_engine/plug_test.exs`
Expected: FAIL — `ElevenLabs.SpeechEngine.Plug` undefined.

- [ ] **Step 3: Create `lib/elevenlabs/speech_engine/plug.ex`**

```elixir
defmodule ElevenLabs.SpeechEngine.Plug do
  @moduledoc """
  A Plug that verifies the ElevenLabs Speech Engine authorization header and, on
  success, upgrades the connection to an `ElevenLabs.SpeechEngine.Session`
  WebSocket.

  Mount it in any Plug/Phoenix router:

      forward "/speech-engine/ws", to: ElevenLabs.SpeechEngine.Plug,
        init_opts: [api_key: System.fetch_env!("ELEVENLABS_API_KEY"), handler: MyAgent]

  Options: `:api_key` (required), `:handler` (required), `:path` (optional exact
  path to enforce), `:debug` (optional boolean).
  """

  @behaviour Plug

  import Plug.Conn

  alias ElevenLabs.SpeechEngine.{JWT, Session}

  @auth_header "x-elevenlabs-speech-engine-authorization"

  @impl true
  def init(opts) do
    %{
      api_key: Keyword.fetch!(opts, :api_key),
      handler: Keyword.fetch!(opts, :handler),
      path: Keyword.get(opts, :path),
      debug: Keyword.get(opts, :debug, false)
    }
  end

  @impl true
  def call(conn, %{api_key: api_key, handler: handler, path: path, debug: debug}) do
    cond do
      path != nil and conn.request_path != path ->
        conn |> send_resp(404, "not found\n") |> halt()

      not authorized?(conn, api_key) ->
        conn |> send_resp(401, "authorization failed\n") |> halt()

      true ->
        conn
        |> WebSockAdapter.upgrade(Session, %{handler: handler, debug: debug}, timeout: 60_000)
        |> halt()
    end
  end

  defp authorized?(conn, api_key) do
    case get_req_header(conn, @auth_header) do
      [value | _] -> match?({:ok, _}, JWT.verify(value, api_key))
      [] -> false
    end
  end
end
```

- [ ] **Step 4: Add `verify_request/2` to `lib/elevenlabs/speech_engine.ex`**

Add `alias ElevenLabs.SpeechEngine.JWT` to the existing aliases, then add this public function (e.g. after `update/3`):

```elixir
  @auth_header "x-elevenlabs-speech-engine-authorization"

  @doc """
  Verifies that a request carries a valid Speech Engine authorization header.
  Accepts a `Plug.Conn` or a headers map/list. Returns a boolean.

  Only needed for fully manual WebSocket integration; `ElevenLabs.SpeechEngine.Plug`
  and `serve/2` verify automatically.
  """
  @spec verify_request(Plug.Conn.t() | map() | list(), String.t()) :: boolean()
  def verify_request(%Plug.Conn{} = conn, api_key) do
    case Plug.Conn.get_req_header(conn, @auth_header) do
      [value | _] -> match?({:ok, _}, JWT.verify(value, api_key))
      [] -> false
    end
  end

  def verify_request(headers, api_key) when is_list(headers) do
    headers |> Map.new(fn {k, v} -> {String.downcase(k), v} end) |> verify_request(api_key)
  end

  def verify_request(headers, api_key) when is_map(headers) do
    downcased = Map.new(headers, fn {k, v} -> {String.downcase(to_string(k)), v} end)

    case Map.get(downcased, @auth_header) do
      nil -> false
      value -> match?({:ok, _}, JWT.verify(value, api_key))
    end
  end
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `mix test test/elevenlabs/speech_engine/plug_test.exs`
Expected: PASS (5 tests).

- [ ] **Step 6: Commit**

```bash
git add lib/elevenlabs/speech_engine/plug.ex lib/elevenlabs/speech_engine.ex test/elevenlabs/speech_engine/plug_test.exs
git commit -m "feat: add verifying Plug and verify_request/2"
```

---

## Task 14: Server (Bandit runner) + `serve/2` + `stop/1`

**Files:**
- Create: `lib/elevenlabs/speech_engine/server.ex`
- Modify: `lib/elevenlabs/speech_engine.ex` (add `serve/2`, `stop/1`)
- Test: `test/elevenlabs/speech_engine/server_start_test.exs`

- [ ] **Step 1: Write the failing test**

```elixir
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
    assert {:ok, pid} = SpeechEngine.serve("sk_test", handler: ElevenLabs.RecordingHandler, port: port)
    assert Process.alive?(pid)
    assert :ok = SpeechEngine.stop(pid)
    refute Process.alive?(pid)
  end

  test "serve/2 accepts a Client and reads its api key" do
    port = free_port()
    client = ElevenLabs.new(api_key: "sk_from_client")
    assert {:ok, pid} = SpeechEngine.serve(client, handler: ElevenLabs.RecordingHandler, port: port)
    on_exit(fn -> if Process.alive?(pid), do: SpeechEngine.stop(pid) end)
    assert Process.alive?(pid)
  end
end
```

- [ ] **Step 2: Run it to verify it fails**

Run: `mix test test/elevenlabs/speech_engine/server_start_test.exs`
Expected: FAIL — `serve/2` undefined.

- [ ] **Step 3: Create `lib/elevenlabs/speech_engine/server.ex`**

```elixir
defmodule ElevenLabs.SpeechEngine.Server do
  @moduledoc """
  Standalone Bandit server that verifies and upgrades Speech Engine connections.

  Add it to a supervision tree:

      {ElevenLabs.SpeechEngine.Server, api_key: key, handler: MyAgent, port: 3001}

  or start it directly with `start_link/1`. Accepts `:api_key`, `:handler`,
  `:port` (default 3001), `:path`, `:debug`, plus any other Bandit options.
  """

  alias ElevenLabs.SpeechEngine.Plug, as: SEPlug

  @plug_keys [:api_key, :handler, :path, :debug]

  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :supervisor,
      restart: :permanent
    }
  end

  def start_link(opts) do
    {plug_opts, bandit_opts} = split(opts)
    Bandit.start_link([plug: {SEPlug, plug_opts}] ++ bandit_opts)
  end

  defp split(opts) do
    plug_opts = Keyword.take(opts, @plug_keys)

    bandit_opts =
      opts
      |> Keyword.drop(@plug_keys)
      |> Keyword.put_new(:port, 3001)

    {plug_opts, bandit_opts}
  end
end
```

- [ ] **Step 4: Add `serve/2` and `stop/1` to `lib/elevenlabs/speech_engine.ex`**

Add `alias ElevenLabs.SpeechEngine.Server` to the aliases, then add:

```elixir
  @doc """
  Starts a standalone Speech Engine WebSocket server (Bandit + verifying Plug)
  and returns `{:ok, pid}`.

  The first argument provides the API key used to verify incoming connections —
  pass an `ElevenLabs.Client` or the key string directly. `opts` requires
  `:handler` and accepts `:port` (default 3001), `:path`, `:debug`.
  """
  @spec serve(Client.t() | String.t(), keyword()) :: {:ok, pid()} | {:error, term()}
  def serve(client_or_key, opts) do
    api_key = resolve_api_key(client_or_key, opts)
    Server.start_link(Keyword.put(opts, :api_key, api_key))
  end

  @doc "Stops a server started by `serve/2`."
  @spec stop(pid()) :: :ok
  def stop(pid) when is_pid(pid), do: Supervisor.stop(pid)

  defp resolve_api_key(%Client{api_key: key}, opts), do: opts[:api_key] || key
  defp resolve_api_key(key, opts) when is_binary(key), do: opts[:api_key] || key
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `mix test test/elevenlabs/speech_engine/server_start_test.exs`
Expected: PASS (2 tests).

- [ ] **Step 6: Commit**

```bash
git add lib/elevenlabs/speech_engine/server.ex lib/elevenlabs/speech_engine.ex test/elevenlabs/speech_engine/server_start_test.exs
git commit -m "feat: add standalone Server, serve/2 and stop/1"
```

---

## Task 15: End-to-end WebSocket test

**Files:**
- Create: `test/support/test_handler.ex`
- Test: `test/elevenlabs/speech_engine/end_to_end_test.exs`

- [ ] **Step 1: Create `test/support/test_handler.ex`**

```elixir
defmodule ElevenLabs.TestHandler do
  @moduledoc false
  use ElevenLabs.SpeechEngine.Handler

  alias ElevenLabs.SpeechEngine.Session

  @impl true
  def handle_transcript(_transcript, session) do
    Session.send_response(session, "hi there")
  end
end
```

- [ ] **Step 2: Write the failing test**

```elixir
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

    {conn, websocket} = send_json(conn, websocket, ref, %{type: "init", conversation_id: "conv_1"})

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
        status = Enum.find_value(responses, fn {:status, ^ref, s} -> s; _ -> nil end)
        headers = Enum.find_value(responses, fn {:headers, ^ref, h} -> h; _ -> nil end)

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
```

- [ ] **Step 3: Run it to verify it passes**

Run: `mix test test/elevenlabs/speech_engine/end_to_end_test.exs`
Expected: PASS (2 tests). If frames arrive split across messages, `recv_text_frames` loops until it sees an `is_final` frame or times out — increase the timeout if a slow CI machine flakes.

- [ ] **Step 4: Run the full suite + format**

Run: `mix format && mix test`
Expected: all green.

- [ ] **Step 5: Commit**

```bash
git add test/support/test_handler.ex test/elevenlabs/speech_engine/end_to_end_test.exs
git commit -m "test: end-to-end WebSocket round trip with Mint.WebSocket"
```

---

## Task 16: README, moduledocs polish, and final verification

**Files:**
- Create: `README.md`
- Modify: any module missing a `@moduledoc` (verify with the compiler warning flag)

- [ ] **Step 1: Create `README.md`**

````markdown
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

## License

MIT
````

- [ ] **Step 2: Verify there are no missing moduledocs or compiler warnings**

Run: `mix compile --warnings-as-errors`
Expected: compiles clean. If a public module reports a missing `@moduledoc`, add a one-line `@moduledoc` describing it (internal modules may use `@moduledoc false`).

- [ ] **Step 3: Run the full suite and formatter check**

Run: `mix format --check-formatted && mix test`
Expected: formatting clean; all tests pass.

- [ ] **Step 4: Commit**

```bash
git add README.md lib/
git commit -m "docs: add README and module documentation"
```

---

## Self-Review

**Spec coverage:**

| Spec requirement | Task |
|---|---|
| `ElevenLabs.new/1`, Client, env fallback, base_url | 2 |
| Error struct + error mapping | 2, 4 |
| Data types (Config/ConversationMessage/Summary/List/Response), config-as-maps | 3 |
| REST list/get/delete + endpoints/params | 4 |
| REST create/update + body shaping (omit absent keys, Config or map) | 5 |
| JWT verification (HS256, sha256(key), iss/sub/exp/iat, leeway, Bearer) | 6 |
| Handler behaviour (required handle_transcript, optional defaults via use) | 7 |
| Session handle + send_response (string/stream, empty-skip, nil-event no-op) | 8 |
| WebSock init/lifecycle (init/ping/close/error/unknown/malformed) + terminate | 9 |
| Transcript dispatch + gated agent_response push | 10 |
| Task completion + crash -> handle_error + final marker | 11 |
| Interruption + duplicate skip | 12 |
| Verifying Plug + verify_request/2 (conn + headers) | 13 |
| Standalone Server + serve/2 ({:ok, pid}) + stop/1 + child_spec | 14 |
| End-to-end JWT handshake + round trip | 15 |
| README + embedding docs | 16 |

No gaps.

**Placeholder scan:** No TBD/TODO; every code/test step contains complete code and exact commands.

**Type consistency:** `%Session{conn, event_id, conversation_id}`, internal message `{:se_chunk, event_id, content, is_final}`, `JWT.verify/2 -> {:ok, payload} | {:error, atom}`, `Config.to_map/1` / `from_json/1`, REST signatures (`list/2`, `get/2`, `delete/2`, `create/2`, `update/3`, `serve/2`, `stop/1`, `verify_request/2`), Plug opts (`api_key`/`handler`/`path`/`debug`), and Server `@plug_keys` are consistent across tasks. Handler callbacks (`handle_init/2`, `handle_transcript/2`, `handle_close/1`, `handle_error/2`) match between the behaviour, the `use` defaults, the test handlers, and the Session dispatch.
