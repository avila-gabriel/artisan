import server/web.{type Context}
import server/web/sales_intake
import wisp.{type Request, type Response}

pub fn handle_request(req: Request, ctx: Context) -> Response {
  use req <- web.middleware(req)

  case wisp.path_segments(req) {
    ["sales_intake"] -> sales_intake.register(req, ctx)
    _ -> wisp.not_found()
  }
}
