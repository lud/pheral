defmodule Pheral.Cowboy.Plug.StaticHelpers do

  @moduledoc """
  Functions copied from Plug.Static because there are private
  """


  def uri_decode(path) do
    try do
      URI.decode(path)
    rescue
      ArgumentError ->
        raise Plug.Static.InvalidPathError
    end
  end

  def path({app, from}, segments) when is_atom(app) and is_binary(from),
    do: Path.join([Application.app_dir(app), from | segments])

  def path(from, segments), do: Path.join([from | segments])

  def subset([h | expected], [h | actual]), do: subset(expected, actual)
  def subset([], actual), do: actual
  def subset(_, _), do: []

  def invalid_path?(list) do
    invalid_path?(list, :binary.compile_pattern(["/", "\\", ":", "\0"]))
  end

  def invalid_path?([h | _], _match) when h in [".", "..", ""], do: true
  def invalid_path?([h | t], match), do: String.contains?(h, match) or invalid_path?(t)
  def invalid_path?([], _match), do: false

end
