use Mix.Config

env = fn name ->
  case System.get_env(name) do
    nil -> throw {:missing_env_var, name}
    other -> other
  end
end

config :moodle_net, MoodleNet.Repo,
  username: env.("DATABASE_USER"),
  password: env.("DATABASE_PASS"),
  database: env.("DATABASE_NAME"),
  hostname: env.("DATABASE_HOST"),
  pool_size: 15

port = String.to_integer(System.get_env("PORT") || "8080")

config :moodle_net, MoodleNetWeb.Endpoint,
  http: [port: port],
  url: [host: env.("HOSTNAME"), port: port],
  root: ".",
  secret_key_base: env.("SECRET_KEY_BASE")

config :moodle_net, :ap_base_url, env.("AP_BASE_URL")

config :moodle_net, :frontend_base_url, env.("FRONTEND_BASE_URL")
<<<<<<< HEAD

=======
  
>>>>>>> Require envvar: FRONTEND_BASE_URL
config :moodle_net, MoodleNet.Mailer,
  domain: env.("MAIL_DOMAIN"),
  api_key: env.("MAIL_KEY")

sentry_dsn = System.get_env("SENTRY_DSN")
sentry_env = System.get_env("SENTRY_ENV")
if not is_nil(sentry_dsn) do
  config :sentry,
    dsn: sentry_dsn,
    environment_name: sentry_env || Mix.env,
    root_source_code_path: File.cwd!,
    enable_source_code_context: true
end
