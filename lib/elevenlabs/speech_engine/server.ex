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
