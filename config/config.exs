use Mix.Config

config :hexagon,
  package_path: "~/packages",
  log_path: "~/package_logs"

config :logger,
  backends: [{LoggerFileBackend, :error_log}]

config :logger, :error_log,
  path: "error.log",
  format: "\n== $time\n$message",
  level: :error

