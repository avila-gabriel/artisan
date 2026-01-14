import gleam/http.{Get, Post}
import gleam/list
import gleam/option.{None, Some}
import server/auth
import server/config
import server/web.{type Context, Context, middleware}
import server/web/login
import server/web/sales_intake
import server/web/serve.{serve}
import wisp.{type Request, type Response}

pub fn handle_request(
  req: Request,
  ctx: Context(auth.Unauthenticated),
) -> Response {
  use req <- middleware(req)

  case wisp.get_cookie(req, config.cookie_name, wisp.Signed) {
    Ok(raw) ->
      case auth.decode_session(raw) {
        Some(session) -> {
          let ctx: Context(auth.Authenticated) =
            Context(..ctx, session: Some(session))
          authenticated_request(req, ctx)
        }
        None -> {
          unauthenticated_request(req)
        }
      }

    Error(_) -> unauthenticated_request(req)
    // TODO: log it
  }
}

pub fn unauthenticated_request(req: Request) -> Response {
  case wisp.path_segments(req) {
    [] ->
      case req.method {
        Get -> login.show()
        Post -> login.submit(req)
        _ -> wisp.method_not_allowed([Get, Post])
      }
    _ -> wisp.not_found()
  }
}

pub fn authenticated_request(
  req: Request,
  ctx: Context(auth.Authenticated),
) -> Response {
  case wisp.path_segments(req) {
    ["sales_intake" as role] ->
      case req.method {
        Get -> serve(ctx, role)
        Post -> sales_intake.register(req, ctx)
        _ -> wisp.method_not_allowed([Get, Post])
      }
    [role] -> {
      case
        list.contains(
          ["purchase, receive, delivery, sales_person, manager"],
          role,
        )
      {
        True if req.method == http.Get -> serve(ctx, role)
        _ -> wisp.not_found()
      }
    }
    _ -> wisp.not_found()
  }
}
