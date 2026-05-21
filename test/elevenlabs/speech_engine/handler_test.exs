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
    behaviours =
      Minimal.module_info(:attributes) |> Keyword.get_values(:behaviour) |> List.flatten()

    assert ElevenLabs.SpeechEngine.Handler in behaviours
  end
end
