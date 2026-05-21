defmodule ElevenLabs.SpeechEngine.Session do
  @moduledoc """
  A Speech Engine conversation session.

  This module is both the `WebSock` callback module (one instance per
  connection) and the `%Session{}` handle passed to `ElevenLabs.SpeechEngine.Handler`
  callbacks. Handlers call `send_response/2` to stream an agent reply back for
  TTS synthesis.
  """

  require Logger

  @behaviour WebSock

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

  def send_response(%__MODULE__{conn: conn, event_id: event_id}, response)
      when is_binary(response) do
    send(conn, {:se_chunk, event_id, response, false})
    send(conn, {:se_chunk, event_id, "", true})
    :ok
  end

  def send_response(%__MODULE__{conn: conn, event_id: event_id}, response) do
    Enum.each(response, fn
      delta when is_binary(delta) and delta != "" ->
        send(conn, {:se_chunk, event_id, delta, false})

      _ ->
        :ok
    end)

    send(conn, {:se_chunk, event_id, "", true})
    :ok
  end

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
  def handle_info({:se_chunk, event_id, content, is_final}, %{current_event_id: current} = state) do
    if event_id == current do
      frame =
        Jason.encode!(%{
          type: "agent_response",
          content: content,
          event_id: event_id,
          is_final: is_final
        })

      {:push, {:text, frame}, state}
    else
      {:ok, state}
    end
  end

  # The async_nolink task finished normally; flush its pending :DOWN and clear it.
  def handle_info({ref, _result}, %{current_task: %Task{ref: ref}} = state)
      when is_reference(ref) do
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

  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) when is_reference(ref),
    do: {:ok, state}

  def handle_info(_msg, state), do: {:ok, state}

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

  defp handle_message(%{"type" => "user_transcript"} = msg, state) do
    incoming = msg["event_id"]

    if duplicate?(incoming, state) do
      {:ok, state}
    else
      state = cancel_current(state)
      transcript = parse_transcript(msg["user_transcript"] || [])

      session = %__MODULE__{
        conn: self(),
        event_id: incoming,
        conversation_id: state.conversation_id
      }

      task =
        Task.Supervisor.async_nolink(ElevenLabs.TaskSupervisor, fn ->
          state.handler.handle_transcript(transcript, session)
        end)

      {:ok, %{state | current_task: task, current_event_id: incoming}}
    end
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

  defp duplicate?(incoming, %{current_event_id: current, current_task: task}) do
    incoming != nil and incoming == current and task != nil and Process.alive?(task.pid)
  end

  defp parse_transcript(list) do
    Enum.map(list, fn msg ->
      %ElevenLabs.SpeechEngine.ConversationMessage{role: msg["role"], content: msg["content"]}
    end)
  end
end
