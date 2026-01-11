import gleam/erlang/process
import gleam/option.{None}
import mist
import server/config
import server/db
import server/migration
import server/router
import server/web
import wisp
import wisp/wisp_mist

pub fn main() {
  wisp.configure_logger()
  let secret_key_base = wisp.random_string(64)
  migration.run()
  let assert Ok(pool) = db.start(config.db_file) as "Lifeguard start error"
  let assert Ok(priv_directory) = wisp.priv_directory("server")
  let static_directory = priv_directory <> "/static"
  let context = web.Context(db: pool, static_directory:, session: None)
  let handler = router.handle_request(_, context)
  let assert Ok(_) =
    handler
    |> wisp_mist.handler(secret_key_base)
    |> mist.new
    |> mist.port(8000)
    |> mist.start
  process.sleep_forever()
}
