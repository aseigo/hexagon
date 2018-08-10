defmodule Hexagon.MixProject do
  use Mix.Project

  def project do
    [
      app: :hexagon,
      version: "0.1.0",
      elixir: "~> 1.7",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger, :inets, :ssl, :erlexec],
      mod: {Hexagon.Application, []}
    ]
  end

  defp deps do
    [
      {:erlexec, "~> 1.9.1"},
      {:flow, "~> 0.14"},
      {:hex_core, "0.1.0"},
      #{:hex_erl, github: "hexpm/hex_erl"},
      {:jason, "~> 1.1.1"},
      {:ok, "~> 1.11.0"},
      {:temp, "~> 0.4"},

      {:coverex, "~> 1.4.15", only: :test},
      {:credo, "~> 0.8.1", only: [:dev, :test]},
      {:dialyxir, "~> 0.5", only: [:test], runtime: false},
      {:ex_doc, "~> 0.18.1", only: :dev},
      {:remix, "~> 0.0.2", only: :dev}
    ]
  end

  def aliases do
    [
      t: [&run_tests/1, "dialyzer", "credo"],
      "db.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      "db.reset": ["ecto.drop", "ecto.setup"],
    ]
  end

  defp run_tests(_) do
    Mix.env(:test)
    Mix.Tasks.Test.run(["--cover", "--stale"])
  end
end
