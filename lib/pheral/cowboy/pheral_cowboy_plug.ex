defmodule Pheral.Cowboy.Plug do
  use Plug.Builder, init_mode: :runtime

  alias Pheral.Cowboy.Plug.StaticHelpers, as: SH

  plug Plug.Logger
  plug :custom_plug_static, builder_opts()
  plug :not_found

  def child_spec(pheral_config) do
    Plug.Cowboy.child_spec(
      scheme: :http,
      plug: {__MODULE__, pheral_config},
      options: cowboy_opts(pheral_config)
    )
  end

  defp cowboy_opts(%{"web" => web}) do
    [port: to_integer(web["port"])]
  end

  defp static_plug_opts(%{"web" => web}) do
    [from: web["docroot"], at: "/"]
  end

  def init(pheral_config) do
    static_opts = static_plug_opts(pheral_config)
    static_plug_state = Plug.Static.init(static_opts)
    %{static: static_plug_state, config: pheral_config}
  end

  def custom_plug_static(conn, %{static: static_plug_state, config: config}) do
    which_service(conn, static_plug_state)
    |> case do
      {:static, path} ->
        Plug.Static.call(conn, static_plug_state)
      {:php, path_data} ->
        {:ok, conn} = Pheral.Cowboy.FastCGI.handle_fcgi(conn, path_data, config)
        Plug.Conn.halt(conn)
    end
  end

  def which_service(conn, static) do
    %{at: at, from: from} = static
    IO.puts "conn #{inspect conn, pretty: true}"
    segments = SH.subset(at, conn.path_info)
    segments = Enum.map(segments, &SH.uri_decode/1)
    if SH.invalid_path?(segments) do
      raise Plug.Static.InvalidPathError
    end
    path = SH.path(from, [])
    IO.puts "conn.path_info        #{inspect conn.path_info}"
    IO.puts "at                    #{inspect at}"
    IO.puts "segments              #{inspect segments}"
    IO.puts "path                  #{inspect path}"
    IO.puts "Path.extname(path)    #{inspect Path.extname(path)}"
    IO.puts "File.regular?(path)   #{inspect File.regular?(path)}"
    which_service_2(path, segments)
  end

  # At each part of the segment, we check if a corresponding file exists, and
  # if true, the remaining segments become PATH_INFO
  def which_service_2(path, [seg|segments] = segments_debug) do
    IO.puts "check path #{path} with #{inspect segments_debug}"
    path = Path.join(path, seg)
    if File.regular?(path) do
      which_service_regular(path, segments)
    else
      which_service_2(path, segments)
    end
  end
  def which_service_2(path, [] = segments_debug) do
    IO.puts "check path #{path} with #{inspect segments_debug}"
    {:php, :catchall}
  end

  def which_service_regular(path, php_path_info_segments) do
    if ".php" === Path.extname(path) do
      {:php, {path, php_path_info_segments}}
    else
      {:static, path}
    end
  end

  def not_found(conn, _) do
    send_resp(conn, 404, "not found")
  end

  defp to_integer(bin) when is_binary(bin),
    do: String.to_integer(bin)
  defp to_integer(int) when is_integer(int),
    do: int

end

