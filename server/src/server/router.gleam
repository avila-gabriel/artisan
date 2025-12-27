import lustre/attribute
import lustre/element
import lustre/element/html
import server/web.{type Context}
import server/web/sales_intake
import wisp.{type Request, type Response}

pub fn handle_request(req: Request, ctx: Context) -> Response {
  use req <- web.middleware(req, ctx)

  case wisp.path_segments(req) {
    [] -> serve_index()
    ["sales_intake"] -> sales_intake.register(req, ctx)
    _ -> wisp.not_found()
  }
}

pub fn serve_index() -> Response {
  let html =
    html.html([], [
      html.head([], [
        html.title([], "Artisan"),
        html.script(
          [attribute.type_("module"), attribute.src("/static/artisan.js")],
          "",
        ),
      ]),
      html.body([], [html.div([attribute.id("app")], [])]),
    ])

  html
  |> element.to_document_string
  |> wisp.html_response(200)
}
