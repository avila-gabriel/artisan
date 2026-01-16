import gleam/list
import gleam/result
import role
import server/auth
import server/config
import wisp.{type Request, type Response}

pub fn show() -> Response {
  let html =
    "<form method='post'>
        <label>
          Username
          <input type='text' name='username'>
        </label>

        <label>
          Password
          <input type='password' name='password'>
        </label>

        <button type='submit'>Login</button>
     </form>"

  wisp.ok()
  |> wisp.html_body(html)
}

pub fn submit(req: Request) -> Response {
  use formdata <- wisp.require_form(req)

  let result = {
    use username <- result.try(list.key_find(formdata.values, "username"))
    use password <- result.try(list.key_find(formdata.values, "password"))
    Ok(#(username, password))
  }

  case result {
    Ok(#(username, password)) ->
      case auth.authenticate(username, password) {
        Ok(#(role, id)) -> {
          let session = auth.Session(id, username, role)
          let value = auth.encode_session(session)

          wisp.redirect("/" <> role.to_string(role))
          |> wisp.set_cookie(
            req,
            config.cookie_name,
            value,
            wisp.Signed,
            60 * 60 * 24 * 30,
          )
        }

        Error(_) -> wisp.redirect("/")
      }

    Error(_) -> wisp.bad_request("Invalid form")
  }
}

pub fn logout(req: Request) -> Response {
  wisp.redirect("/")
  |> wisp.set_cookie(req, config.cookie_name, "", wisp.Signed, 0)
}
