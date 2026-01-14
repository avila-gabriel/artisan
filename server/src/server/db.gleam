import gleam/erlang/process.{type Name, type Subject}
import gleam/otp/actor
import gleam/otp/static_supervisor as supervisor
import gleam/otp/supervision
import gleam/result
import lifeguard
import parrot/dev
import sqlight.{type Connection, type Error, SqlightError}

pub type Pool =
  Subject(lifeguard.PoolMsg(WorkerMsg))

pub type WorkerMsg {
  GetConn(reply_to: Subject(Connection))
}

pub fn start(db_file: String) -> Result(Pool, actor.StartError) {
  let pool_name: Name(lifeguard.PoolMsg(WorkerMsg)) =
    process.new_name("sqlite_pool")

  let builder =
    lifeguard.new_with_initialiser(pool_name, 5000, fn(_self) {
      case open_connection(db_file) {
        Ok(conn) -> Ok(lifeguard.initialised(conn))

        Error(_) -> Error("sqlite init failed")
      }
    })
    |> lifeguard.size(6)
    |> lifeguard.on_message(handle_worker_msg)

  let spec: supervision.ChildSpecification(supervisor.Supervisor) =
    lifeguard.supervised(builder, 5000)

  supervisor.new(supervisor.OneForOne)
  |> supervisor.add(spec)
  |> supervisor.start
  |> result.map(fn(_pid) { process.named_subject(pool_name) })
}

fn apply_error_to_sqlight_error(err: lifeguard.ApplyError) -> Error {
  case err {
    lifeguard.NoResourcesAvailable ->
      SqlightError(
        code: sqlight.Busy,
        message: "No SQLite connections available",
        offset: -1,
      )
  }
}

fn handle_worker_msg(
  conn: Connection,
  msg: WorkerMsg,
) -> actor.Next(Connection, WorkerMsg) {
  case msg {
    GetConn(reply_to:) -> {
      process.send(reply_to, conn)
      actor.continue(conn)
    }
  }
}

pub fn with_connection(
  pool: Pool,
  checkout_timeout: Int,
  call_timeout: Int,
  run: fn(Connection) -> a,
) -> Result(a, Error) {
  case
    lifeguard.apply(pool, checkout_timeout, fn(worker_subject) {
      process.call(worker_subject, call_timeout, fn(reply_to) {
        GetConn(reply_to:)
      })
    })
  {
    Error(apply_err) -> Error(apply_error_to_sqlight_error(apply_err))
    Ok(conn) -> Ok(run(conn))
  }
}

pub fn with_transaction(
  pool: Pool,
  checkout_timeout: Int,
  call_timeout: Int,
  run: fn(Connection) -> Result(a, Error),
) -> Result(a, Error) {
  case
    with_connection(pool, checkout_timeout, call_timeout, fn(conn) {
      case sqlight.exec("BEGIN IMMEDIATE;", conn) {
        Error(e) -> Error(e)

        Ok(_) ->
          case run(conn) {
            Ok(val) ->
              case sqlight.exec("COMMIT;", conn) {
                Ok(_) -> Ok(val)
                Error(e) -> {
                  let _ = sqlight.exec("ROLLBACK;", conn)
                  Error(e)
                }
              }

            Error(e) -> {
              let _ = sqlight.exec("ROLLBACK;", conn)
              Error(e)
            }
          }
      }
    })
  {
    Ok(Ok(val)) -> Ok(val)
    Ok(Error(e)) -> Error(e)
    Error(e) -> Error(e)
  }
}

pub fn open_connection(db_file: String) -> Result(Connection, Error) {
  case sqlight.open("file:" <> db_file <> "?mode=rwc") {
    Error(e) -> Error(e)
    Ok(conn) -> {
      let _ = sqlight.exec("PRAGMA journal_mode = WAL;", conn)
      let _ = sqlight.exec("PRAGMA synchronous = NORMAL;", conn)
      let _ = sqlight.exec("PRAGMA foreign_keys = ON;", conn)
      let _ = sqlight.exec("PRAGMA busy_timeout = 5000;", conn)
      Ok(conn)
    }
  }
}

pub fn parrot_to_sqlight(param: dev.Param) -> sqlight.Value {
  case param {
    dev.ParamFloat(x) -> sqlight.float(x)
    dev.ParamInt(x) -> sqlight.int(x)
    dev.ParamString(x) -> sqlight.text(x)
    dev.ParamBitArray(x) -> sqlight.blob(x)
    dev.ParamNullable(x) -> sqlight.nullable(fn(a) { parrot_to_sqlight(a) }, x)
    dev.ParamList(_) -> panic as "sqlite does not implement lists"
    dev.ParamBool(_) -> panic as "sqlite does not support booleans"
    dev.ParamDate(_) -> panic as "sqlite does not support dates"
    dev.ParamTimestamp(_) -> panic as "sqlite does not support timestamps"
    dev.ParamDynamic(_) -> panic as "sqlite dynamic not implemented"
  }
}
