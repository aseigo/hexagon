use Mix.Config

config :logger,
  backends: [{LoggerFileBackend, :error_log}]

config :logger, :error_log,
  path: "error.log",
  format: "\n== $time\n$message",
  level: :error

