import envoy
import gleam/erlang/process
import gleam/int
import gleam/option.{None}
import gleam/result
import mist
import server/auth
import server/config
import server/db
import server/migration
import server/router
import server/web
import wisp
import wisp/wisp_mist

pub fn main() {
  let assert Ok(port) = envoy.get("PORT") |> result.unwrap("8000") |> int.parse
    as "Environment var PORT is not a int-parsable"

  wisp.configure_logger()
  let secret_key_base = wisp.random_string(64)

  let assert Ok(Nil) = migration.run() as "Migration failed"

  let assert Ok(pool) = db.start(config.db_file)
    as "Database pooling connection failed"

  let assert Ok(priv_directory) = wisp.priv_directory(config.package_name)
    as { "No package found with the given name" <> config.package_name }

  let static_directory = priv_directory <> "/static"
  let context: web.Context(auth.Unauthenticated) =
    web.Context(db: pool, static_directory:, session: None)
  let handler = router.handle_request(_, context)

  let assert Ok(_) =
    handler
    |> wisp_mist.handler(secret_key_base)
    |> mist.new
    |> mist.port(port)
    |> mist.start
    as "Mist start failed"

  process.sleep_forever()
}
