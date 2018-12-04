defmodule Pheral.MixProject do
  use Mix.Project

  def project do
    [
      app: :pheral,
      version: "0.1.0",
      elixir: "~> 1.7",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      # erlc_options:  [{:i, 'deps/yaws/include'}],
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {Pheral.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:yaws, git: "#{System.get_env("HOME")}/src/yaws", runtime: false, compile: compile_yaws_cmd},
      # {:yaws, git: "#{System.get_env("HOME")}/src/yaws", runtime: false, manager: :rebar},
      {:jason, "~> 1.1"},
      # {:dep_from_git, git: "https://github.com/elixir-lang/my_dep.git", tag: "0.1.0"},
    ]
  end

  defp compile_yaws_cmd do
    build_dir = File.cwd!
      |> Path.join(["_build", to_string(Mix.env()), "lib", "yaws"])
      |> Path.expand
    [
      "autoreconf -fi",
      "./configure --prefix=#{build_dir}",
      "make",
    ] |> Enum.join(" && ")
  end

end
