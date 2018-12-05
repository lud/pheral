defmodule Pheral.Cowboy.FastCGI do
  require Logger
  @client_name :'pheral-fpm'

  def handle_fcgi(conn, :catchall, config),
    do: handle_fcgi(conn, config["web"]["catchall"], config)

  def handle_fcgi(conn, phpscript, config) do
    IO.puts "serve with php : #{phpscript}"
    %{adapter: {Plug.Cowboy.Conn, req}} = conn
    opts = fcgi_opts(phpscript, config)
    {:ok, req, _} = :cowboy_http_fcgi.init(req, opts)
    conn = req
      |> Plug.Cowboy.Conn.conn()
      |> Map.put(:state, :sent)
    {:ok, conn}
  end

  defp fcgi_opts(phpscript, config) do
    # {name, atom()}
    # | {timeout, uint32()}
    # | {script_dir, iodata()}
    # | {path_root, iodata()}
    [
      name: @client_name,
      script_dir: to_charlist(config["web"]["docroot"])
    ]
  end

  def fcgi_client_child_spec(config) do
    # :debugger.start()
    # :int.ni(:cowboy_http_fcgi)
    # :int.ni(:ex_fcgi)
    # :int.ni(:ex_fcgi_protocol)
    # :int.break(:ex_fcgi, 86)

    Logger.error "Faut reimplementer le handler fastcgi pour gérer les URL dynamiques ..."

    name = @client_name
    address = {127,0,0,1}
    port = config["web"]["fpmport"]
    IO.puts "fcgi opts: #{inspect([name, address, port], pretty: true)}"
    Supervisor.Spec.worker(:ex_fcgi, [name, address, port], id: Module.concat(__MODULE__, Client))
  end
end
