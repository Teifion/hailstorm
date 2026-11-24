defmodule Hailstorm.ConfigHelpers do
  @moduledoc false
  def to_bool(v) when v in [nil, "", "false", "0"], do: false
  def to_bool(v) when v in ["true", "1"], do: true
end
