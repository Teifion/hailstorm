import Config

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :hailstorm, HailstormWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4005],
  secret_key_base: "PSDHI2YJX8X1QpL+t6v+R6mDTGa+ppMdrPC5Cppr9zu10pAa3yYmVZct+DBLtMkP",
  server: false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true
