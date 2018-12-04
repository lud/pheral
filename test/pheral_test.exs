defmodule PheralTest do
  use ExUnit.Case
  doctest Pheral

  test "greets the world" do
    assert Pheral.hello() == :world
  end
end
