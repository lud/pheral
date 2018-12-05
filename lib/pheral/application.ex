defmodule Pheral.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  def start(_type, _args) do

    exsync_start()
    HTTPoison.start

    # List all child processes to be supervised
    config = Pheral.Config.load()
    children = [
      # {Pheral.Yaws.Sup, config},
      # Starts a worker by calling: Pheral.Worker.start_link(arg)
      Pheral.Cowboy.FastCGI.fcgi_client_child_spec(config),
      {Pheral.Cowboy.Plug, config},
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Pheral.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp exsync_start() do
    case Code.ensure_loaded(ExSync) do
      {:module, ExSync} -> ExSync.start()
      {:error, :nofile} -> :ok
    end
  end

end
