import gleam/http.{Get, Post}
import gleam/list
import gleam/option.{None, Some}
import server/auth
import server/web.{type Context, Context, middleware}
import server/web/login
import server/web/sales_intake
import server/web/serve.{serve}
import wisp.{type Request, type Response}

pub fn handle_request(req: Request, ctx: Context) -> Response {
  use req <- middleware(req)

  let ctx = case wisp.get_cookie(req, "session", wisp.Signed) {
    Ok(raw) ->
      case auth.decode_session(raw) {
        Some(session) -> Context(..ctx, session: Some(session))
        None -> ctx
      }

    Error(_) -> ctx
    // TODO: log it
  }

  case wisp.path_segments(req) {
    [] ->
      case req.method {
        Get -> login.show(req, ctx)
        Post -> login.submit(req, ctx)
        _ -> wisp.method_not_allowed([Get, Post])
      }

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
        True -> serve(ctx, role)
        False -> wisp.not_found()
      }
    }
    _ -> wisp.not_found()
  }
}
