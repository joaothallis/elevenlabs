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
