defmodule CodeAgent.MixProject do
  use Mix.Project

  def project do
    [
      app: :code_agent,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {CodeAgent.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:langchain, "~> 0.3.3"},
      {:plug_cowboy, "~> 2.6"},
      {:cors_plug, "~> 3.0"}
    ]
  end
end
