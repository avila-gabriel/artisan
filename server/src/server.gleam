import gleam/erlang/process
import mist
import wisp
import wisp/wisp_mist

import app/router
import app/web
import db

pub const data_directory = "tmp/data"

pub const db_file = data_directory <> "/data.db"

pub fn main() {
  wisp.configure_logger()

  let secret_key_base = wisp.random_string(64)

  let assert Ok(pool) = db.start(db_file)

  let context = web.Context(db: pool)

  let handler = router.handle_request(_, context)

  let assert Ok(_) =
    handler
    |> wisp_mist.handler(secret_key_base)
    |> mist.new
    |> mist.port(8000)
    |> mist.start

  process.sleep_forever()
}
