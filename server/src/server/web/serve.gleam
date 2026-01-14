import gleam/option.{None, Some}
import lustre/attribute
import lustre/element
import lustre/element/html
import server/auth
import server/web.{type Context}
import wisp.{type Response}

pub fn serve(ctx: Context(auth.Authenticated), role: String) -> Response {
  case ctx.session {
    None -> wisp.redirect("/")

    Some(_) ->
      html.html([], [
        html.head([], [
          html.script(
            [
              attribute.type_("module"),
              attribute.src("/static/" <> role <> ".js"),
            ],
            "",
          ),
        ]),
        html.body([], [
          html.div([attribute.id("app")], []),
        ]),
      ])
      |> element.to_document_string
      |> wisp.html_response(200)
  }
}
