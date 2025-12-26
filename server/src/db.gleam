import gleam/erlang/process.{type Name, type Subject}
import gleam/otp/actor
import gleam/otp/static_supervisor as supervisor
import gleam/otp/supervision
import gleam/result
import lifeguard
import sqlight.{type Connection, type Error}

pub type Pool(a) =
  Subject(lifeguard.PoolMsg(Msg(a)))

/// Internal worker protocol.
/// We never expose this outside the module.
pub type Msg(a) {
  WithConn(run: fn(Connection) -> a, reply_to: Subject(Result(a, Error)))

  WithTx(
    run: fn(Connection) -> Result(a, Error),
    reply_to: Subject(Result(a, Error)),
  )
}

/// ---- Public API ----
/// Start the SQLite pool (call once at startup).
pub fn start(db_file: String) -> Result(Pool(a), actor.StartError) {
  let pool_name: Name(lifeguard.PoolMsg(Msg(a))) =
    process.new_name("sqlite_pool")

  let builder =
    lifeguard.new_with_initialiser(pool_name, 5000, fn(_self) {
      open_connection(db_file)
      |> result.map(lifeguard.initialised)
      |> result.map_error(fn(_) { "sqlite init failed" })
    })
    |> lifeguard.size(6)
    |> lifeguard.on_message(handle_msg)

  let spec: supervision.ChildSpecification(supervisor.Supervisor) =
    lifeguard.supervised(builder, 5000)

  let assert Ok(_) =
    supervisor.new(supervisor.OneForOne)
    |> supervisor.add(spec)
    |> supervisor.start

  Ok(process.named_subject(pool_name))
}

/// Run a function with a pooled connection.
/// Intended for reads or non-transactional work.
pub fn with_connection(
  pool: Pool(a),
  checkout_timeout: Int,
  call_timeout: Int,
  run: fn(Connection) -> a,
) -> Result(Result(a, Error), lifeguard.ApplyError) {
  lifeguard.call(
    pool,
    fn(reply_to) { WithConn(run:, reply_to:) },
    checkout_timeout,
    call_timeout,
  )
}

/// Run a function inside a transaction.
/// Intended for writes.
pub fn with_transaction(
  pool: Pool(a),
  checkout_timeout: Int,
  call_timeout: Int,
  run: fn(Connection) -> Result(a, Error),
) -> Result(Result(a, Error), lifeguard.ApplyError) {
  lifeguard.call(
    pool,
    fn(reply_to) { WithTx(run:, reply_to:) },
    checkout_timeout,
    call_timeout,
  )
}

/// ---- Worker implementation ----
pub fn handle_msg(
  conn: Connection,
  msg: Msg(a),
) -> actor.Next(Connection, Msg(a)) {
  case msg {
    WithConn(run:, reply_to:) -> {
      let result = Ok(run(conn))
      process.send(reply_to, result)
      actor.continue(conn)
    }

    WithTx(run:, reply_to:) -> {
      let _ = sqlight.exec("BEGIN IMMEDIATE;", conn)

      let result = case run(conn) {
        Ok(val) -> {
          let _ = sqlight.exec("COMMIT;", conn)
          Ok(val)
        }
        Error(err) -> {
          let _ = sqlight.exec("ROLLBACK;", conn)
          Error(err)
        }
      }

      process.send(reply_to, result)
      actor.continue(conn)
    }
  }
}

/// ---- Connection bootstrap ----
pub fn open_connection(db_file: String) -> Result(Connection, Error) {
  use conn <- result.try(sqlight.open("file:" <> db_file <> "?mode=rwc"))

  let _ = sqlight.exec("PRAGMA journal_mode = WAL;", conn)
  let _ = sqlight.exec("PRAGMA synchronous = NORMAL;", conn)
  let _ = sqlight.exec("PRAGMA foreign_keys = ON;", conn)
  let _ = sqlight.exec("PRAGMA busy_timeout = 5000;", conn)

  Ok(conn)
}
