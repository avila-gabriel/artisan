import gleam/erlang/application
import migrant
import server/config
import sqlight

pub fn run() {
  let conn = case sqlight.open("file:" <> config.db_file <> "?mode=rwc") {
    Error(sqlight.SqlightError(sqlight.Cantopen, "", -1)) ->
      panic as "SQLite3 connection failed during migration, check the db path"
    Error(_) -> panic as "SQLite3 connection failed during migration"
    Ok(conn) -> conn
  }

  let assert Ok(priv_directory) =
    application.priv_directory(config.package_name)
    as { "No package found with the given name" <> config.package_name }

  migrant.migrate(conn, priv_directory <> "/migrations")
}
