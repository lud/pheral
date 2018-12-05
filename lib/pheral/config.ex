defmodule Pheral.Config do
  require Logger
  @config_fname "pheral.json"

  def load() do

    find_config_file()
    |> load_file()
  end

  defp find_config_file() do
    in_release = Path.join(System.get_env("OLDPWD"), @config_fname)
    in_mix = Path.join(File.cwd!(), @config_fname)
    cond do
      File.exists?(in_release) -> in_release
      File.exists?(in_mix) -> in_mix
      true -> nil
    end
  end

  def load_file(nil) do
    Logger.warn("Config file not found")
    load_config(%{})
  end

  def load_file(path) do
    try do
      path
        |> File.read!()
        |> Jason.decode!()
        |> load_config
    rescue e in Jason.DecodeError ->
        errmsg = Jason.DecodeError.message(e)
        errmsg = "Error while parsin json in #{path} : #{errmsg}"
        Logger.error(errmsg)
        raise errmsg
    end
  end

  defp load_config(map) when is_map(map) do
    map
    |> apply_defaults()
    |> apply_transforms()
  end

  defp apply_defaults(map) do
    map
    |> Map.put_new("web", %{})
  end

  defp apply_transforms(map) do
    map
    |> Map.update!("web", &apply_web_defaults/1)
    |> Map.update!("web", &apply_web_transforms/1)
  end

  defp apply_web_defaults(web) when is_map(web) do
    web = web
    |> Map.put_new("docroot", "public")
    web
    |> Map.put_new("catchall", Path.join(web["docroot"], "index.php"))
    |> Map.put_new("logdir", "logs")
    |> Map.put_new("port", 8000)
    |> Map.put_new("fpmport", 9999)
    |> Map.put_new("listen", "127.0.0.1")
  end

  defp apply_web_transforms(web) when is_map(web) do
    web
    |> Map.update!("docroot", &Path.expand/1)
    |> Map.update!("catchall", &Path.expand/1)
    |> Map.update!("logdir", &Path.expand/1)
  end

end
