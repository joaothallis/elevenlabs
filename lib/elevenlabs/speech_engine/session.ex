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
end
