defmodule Pheral.Cowboy.FastCGI do
  require Logger
  @client_name :'pheral-fpm'

  def handle_fcgi(conn, :catchall, config),
    do: handle_fcgi(conn, {config["web"]["catchall"], []}, config)

  def handle_fcgi(conn, {php_file, php_path_info_segments}, config) do
    %{adapter: {Plug.Cowboy.Conn, req}} = conn
    opts = fcgi_opts({php_file, php_path_info_segments}, config)
    fcgi_client_pid = opts[:name]
    {:ok, req, _} = :cowboy_pheral_fcgi.init(req, opts)
    conn = req
      |> Plug.Cowboy.Conn.conn()
      |> Map.put(:state, :sent)
    send(fcgi_client_pid, :stop)
    {:ok, conn}
  end

  defp fcgi_opts({php_file, php_path_info_segments}, config) do
    # {name, atom()}
    # | {timeout, uint32()}
    # | {script_dir, iodata()}
    # | {path_root, iodata()}
    address = {127,0,0,1}
    port = config["web"]["fpmport"]
    IO.puts "php_file #{inspect php_file}"
    {:ok, pid} = start_fcgi_client(address, port)
    [
      name: pid,
      script_name: Path.relative_to(php_file, config["web"]["docroot"]),
      script_dir: config["web"]["docroot"],
      php_path_info: join_path_info(php_path_info_segments),
    ]
  end

  def start_fcgi_client(address, port) do
    :ex_fcgi_anon.start_link(address, port)
  end


  defp join_path_info([]), do: ""
  defp join_path_info(segments), do: [?/, Enum.join(segments, "/")]

end
