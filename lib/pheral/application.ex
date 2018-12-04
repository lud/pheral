defmodule Pheral.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  def start(_type, _args) do
    # List all child processes to be supervised
    config = Pheral.Config.load()
    IO.puts("Pheral config : #{inspect(config, pretty: true)}")
    children = [
      {Pheral.Yaws.Sup, config},
      # Starts a worker by calling: Pheral.Worker.start_link(arg)
      # {Pheral.Worker, arg},
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Pheral.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
