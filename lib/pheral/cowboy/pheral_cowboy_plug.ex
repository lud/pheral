defmodule Pheral.Cowboy.Plug do
  use Plug.Builder, init_mode: :runtime

  alias Pheral.Cowboy.Plug.StaticHelpers, as: SH

  plug Plug.Logger
  plug :custom_plug_static, builder_opts()
  plug :not_found

  @pheral_yaws to_charlist('pheral')

  def child_spec(pheral_config) do

    %{"web" => web} = pheral_config

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
    IO.puts "init pheral_config : #{inspect pheral_config}"
    static_opts = static_plug_opts(pheral_config)
    IO.puts "custom_plug_static static_opts : #{inspect static_opts, pretty: true}"
    static_plug_state = Plug.Static.init(static_opts)
    IO.puts "static_plug_state : #{inspect static_plug_state, pretty: true}"
    %{static: static_plug_state, config: pheral_config}
  end

  def custom_plug_static(conn, %{static: static_plug_state, config: config}) do
    which_service(conn, static_plug_state)
    |> IO.inspect
    |> case do
      :static ->
        {Plug.Cowboy.Conn, req} = conn.adapter
        IO.puts "serve with static, req: #{inspect req, pretty: true}"
        Plug.Static.call(conn, static_plug_state)
      {:php, path} ->
        {:ok, conn} = Pheral.Cowboy.FastCGI.handle_fcgi(conn, path, config)
        # Plug.Conn.halt(conn)
        Plug.Conn.halt(conn)
    end
  end

  def which_service(conn, static) do
    %{at: at, only: only, prefix: prefix, from: from} = static
    segments = SH.subset(at, conn.path_info)
    segments = Enum.map(segments, &SH.uri_decode/1)
    if SH.invalid_path?(segments) do
      raise InvalidPathError
    end
    path = SH.path(from, segments)
    IO.puts "is php path : #{inspect(path, pretty: true)} "
    cond do
      # A PHP file
      File.regular?(path) && ".php" === Path.extname(path) ->
        {:php, path}
      # Anoher file
      File.regular?(path) ->
        :static
      # Default
      true ->
        {:php, :catchall}
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

