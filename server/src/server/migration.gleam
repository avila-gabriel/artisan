import gleam/erlang/application
import migrant
import server/config
import sqlight

pub fn run() {
  let assert Ok(conn) = sqlight.open("file:" <> config.db_file <> "?mode=rwc")
    as "Didnt open"

  let assert Ok(priv_directory) = application.priv_directory("server")

  let assert Ok(_) = migrant.migrate(conn, priv_directory <> "/migrations")

  Nil
}
