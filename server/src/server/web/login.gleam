import common
import formal/form.{type Form}
import lustre/attribute
import lustre/element
import lustre/element/html
import server/auth
import server/web.{type Context}
import wisp.{type Request, type Response}

const cookie_name = "session"

pub type Data {
  Data(username: String, password: String)
}

fn form() -> Form(Data) {
  form.new({
    use username <- form.field("username", form.parse_string)
    use password <- form.field("password", form.parse_string)
    form.success(Data(username:, password:))
  })
}

pub fn show(_req: Request, _ctx: Context) -> Response {
  html.html([], [
    html.head([], [
      html.title([], ""),
    ]),
    html.body([], [
      html.form([attribute.method("POST")], [
        html.input([
          attribute.type_("text"),
          attribute.name("username"),
        ]),
        html.input([
          attribute.type_("password"),
          attribute.name("password"),
        ]),
        html.button([], [html.text("")]),
      ]),
    ]),
  ])
  |> element.to_document_string
  |> wisp.html_response(200)
}

pub fn submit(req: Request, _ctx: Context) -> Response {
  use formdata <- wisp.require_form(req)

  let form =
    form()
    |> form.add_values(formdata.values)

  case form.run(form) {
    Ok(Data(username, password)) ->
      case auth.authenticate(username, password) {
        Ok(role) -> {
          let session = auth.Session(1, username, role)
          let value = auth.encode_session(session)

          wisp.redirect("/" <> common.role_to_string(role))
          |> wisp.set_cookie(
            req,
            cookie_name,
            value,
            wisp.Signed,
            60 * 60 * 24 * 30,
          )
        }

        Error(_) -> wisp.redirect("/")
      }

    Error(_) -> wisp.redirect("/")
  }
}

pub fn logout(req: Request, _ctx: Context) -> Response {
  wisp.redirect("/")
  |> wisp.set_cookie(req, cookie_name, "", wisp.Signed, 0)
}
