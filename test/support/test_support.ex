defmodule ElevenLabs.TestSupport do
  @moduledoc false

  @doc "Registers `pid` as the recipient for test-handler callback messages."
  def set_test_pid(pid), do: Application.put_env(:elevenlabs, :test_pid, pid)

  @doc "The pid that test handlers send callback notifications to."
  def test_pid, do: Application.get_env(:elevenlabs, :test_pid)

  @doc "Wraps a map as a `WebSock` text frame, as `handle_in/2` expects."
  def frame(map), do: {Jason.encode!(map), [opcode: :text]}
end
