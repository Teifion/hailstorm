defmodule Hailstorm.IdleConn do
  @moduledoc """
  Simply establish a tachyon connection and then do nothing.

  Useful for testing/debugging hailstorm itself, or to just see how many
  connection can be established
  """

  use Hailstorm.TachyonWorker
end
