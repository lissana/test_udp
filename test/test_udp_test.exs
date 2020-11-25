defmodule TestUdpTest do
  use ExUnit.Case
  doctest TestUdp

  test "greets the world" do
    assert TestUdp.hello() == :world
  end
end
