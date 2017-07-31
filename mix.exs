defmodule GenLoop.Mixfile do
  use Mix.Project

  def project do
    [app: :gen_loop,
     description: """
     A supervised free-form loop function. Elixir adapter for plain_fsm, with
     receive / sync-call macros and GenServer-like starting, stopping and name
     registration.
     """,
     version: "0.1.0",
     elixir: "~> 1.4",
     build_embedded: Mix.env == :prod,
     start_permanent: Mix.env == :prod,
     name:" GenLoop",
     deps: deps()]
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
      {:plain_fsm, github: "uwiger/plain_fsm", commit: "ae9eca8a8df8f61a32185b06882a55d60e62e904"},
      {:ex_doc, "~> 0.14", only: :dev},
    ]
  end

  defp package() do
    [
      licenses: ["MIT"],
      maintainers: ["niahoo osef <dev@ooha.in>"],
      links: %{"Github" => "https://github.com/niahoo/gen_loop"},
    ]
  end
end
