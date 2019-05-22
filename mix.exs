defmodule GenLoop.Mixfile do
  use Mix.Project

  def project do
    [
      app: :gen_loop,
      description: """
      A supervised free-form loop function. Elixir adapter for plain_fsm, with
      receive / sync-call macros and GenServer-like starting, stopping and name
      registration.
      """,
      version: "1.0.0",
      elixir: "~> 1.4",
      build_embedded: Mix.env() == :prod,
      deps: deps(),
      name: "GenLoop",
      package: package()
    ]
  end

  # Configuration for the OTP application
  #
  # Type "mix help compile.app" for more information
  def application do
    # Specify extra applications you'll use from Erlang/Elixir
    [extra_applications: [:logger]]
  end

  defp deps do
    [
      # {:plain_fsm, "== 1.4.0"}, # Hard version because of records
      {:plain_fsm,
       github: "uwiger/plain_fsm",
       commit: "1de45fba4caccbc76df0b109e7581d0fc6a2e67b"},
      {:ex_doc, "~> 0.14", only: :dev}
    ]
  end

  defp package() do
    [
      licenses: ["MIT"],
      maintainers: ["Ludovic Demblans <ludovic@demblans.com>"],
      links: %{"Github" => "https://github.com/lud/gen_loop"}
    ]
  end
end
