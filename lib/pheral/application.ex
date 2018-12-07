defmodule Pheral.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false
  require Logger
  use Application

  def start(_type, _args) do

    check_dev_env()


    # List all child processes to be supervised
    config = Pheral.Config.load()
    IO.puts "Pheral config : #{inspect(config, pretty: true)}"
    children = [
      # {Pheral.Yaws.Sup, config},
      # Starts a worker by calling: Pheral.Worker.start_link(arg)
      {Pheral.Cowboy.Plug, config},
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Pheral.Supervisor]
    Supervisor.start_link(children, opts)
  end

  def check_dev_env do
    if Code.ensure_compiled?(Mix) do
      case Mix.env() do
        :dev ->
          Logger.debug "Starting ExSync"
          ExSync.start()
          # HTTPoison.start
      end
    end
  end

end
