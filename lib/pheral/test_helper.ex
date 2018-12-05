defmodule Pheral.TestHelper do
  import IO, only: [puts: 1]

  def get_index_php do
    # get_http("http://localhost:8000/index.php?lol=haha#some-id")
    # get_http("http://localhost:8000/aaa/bbb?xd=ptdr")
    get_http("http://localhost:8000/")
  end

  defp get_http(url) do
    # spawn(fn ->
    #   %{headers: headers, body: body} = HTTPoison.get!(url)
    #   puts '--------'
    #   headers
    #   |> Enum.map(fn {k, v} -> "#{k}: #{v}" end)
    #   |> Enum.join("\n")
    #   |> puts
    #   puts "\n"
    #   # puts body
    #   puts '--------'
    # end)
  end

end
