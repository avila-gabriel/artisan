import gleam/dynamic/decode
import gleam/result
import gleeunit
import server/db
import simplifile
import sqlight

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn db_persistence_test() {
  let db_file = "data/test.sqlite"

  let _ = simplifile.create_directory("data")
  let _ = simplifile.delete(db_file)

  let assert Ok(pool1) = db.start(db_file)

  let assert Ok(_) =
    db.with_transaction(pool1, 5000, 5000, fn(conn) {
      let assert Ok(_) =
        sqlight.exec(
          "CREATE TABLE IF NOT EXISTS persist_test (value TEXT NOT NULL);",
          conn,
        )

      let assert Ok(_) =
        sqlight.exec(
          "INSERT INTO persist_test (value) VALUES ('it persists');",
          conn,
        )

      Ok(Nil)
    })

  // Read immediately (note: rows are arrays, so we decode each row as List(String))
  let assert Ok(values1) =
    db.with_connection(pool1, 5000, 5000, fn(conn) {
      sqlight.query(
        "SELECT value FROM persist_test;",
        on: conn,
        with: [],
        expecting: decode.list(decode.string),
      )
    })
    |> result.flatten

  assert values1 == [["it persists"]]

  // Second start (same file, new pool, same VM)
  let assert Ok(pool2) = db.start(db_file)

  let assert Ok(values2) =
    db.with_connection(pool2, 5000, 5000, fn(conn) {
      sqlight.query(
        "SELECT value FROM persist_test;",
        on: conn,
        with: [],
        expecting: decode.list(decode.string),
      )
    })
    |> result.flatten

  assert values2 == [["it persists"]]
}
