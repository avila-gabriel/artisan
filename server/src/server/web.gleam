import gleam/option.{type Option}
import server/auth
import server/db
import wisp.{type Request, type Response}

pub type Context {
  Context(db: db.Pool, static_directory: String, session: Option(auth.Session))
}

pub fn middleware(
  req: Request,
  handle_request: fn(Request) -> Response,
) -> Response {
  let req = wisp.method_override(req)
  use <- wisp.log_request(req)
  use <- wisp.rescue_crashes
  use req <- wisp.handle_head(req)
  use req <- wisp.csrf_known_header_protection(req)
  use <- wisp.serve_static(req, under: "/static", from: "./priv/static")

  handle_request(req)
}
