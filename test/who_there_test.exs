defmodule WhoThereTest do
  use ExUnit.Case
  doctest WhoThere

  test "greets the world" do
    assert WhoThere.hello() == :world
  end
end
