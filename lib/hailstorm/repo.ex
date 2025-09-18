defmodule Hailstorm.Repo do
  use Ecto.Repo, otp_app: :hailstorm, adapter: Ecto.Adapters.SQLite3
end
