defmodule Pheral.Cowboy.FastCGI do
  require Logger
  @client_name :'pheral-fpm'

  def handle_fcgi(conn, :catchall, config),
    do: handle_fcgi(conn, config["web"]["catchall"], config)

  def handle_fcgi(conn, php_file, config) do
    %{adapter: {Plug.Cowboy.Conn, req}} = conn
    opts = fcgi_opts(php_file, config)
    {:ok, req, _} = :cowboy_pheral_fcgi.init(req, opts)
    conn = req
      |> Plug.Cowboy.Conn.conn()
      |> Map.put(:state, :sent)
    {:ok, conn}
  end

  defp fcgi_opts(php_file, config) do
    # {name, atom()}
    # | {timeout, uint32()}
    # | {script_dir, iodata()}
    # | {path_root, iodata()}
    [
      name: @client_name,
      script_name: Path.relative_to(php_file, config["web"]["docroot"]),
      script_dir: config["web"]["docroot"],
    ]
  end

  def fcgi_client_child_spec(config) do
    name = @client_name
    address = {127,0,0,1}
    port = config["web"]["fpmport"]
    Supervisor.Spec.worker(:ex_fcgi, [name, address, port], id: Module.concat(__MODULE__, Client))
  end
end
