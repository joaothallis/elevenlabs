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
  def handle_info(_msg, state) do
    {:ok, state}
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
end
