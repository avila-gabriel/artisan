import common.{type Role, SalesIntakeRole}
import formal/form.{type Form}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import shared.{view_input}

pub fn new_login_form() -> Form(LoginData) {
  form.new({
    use username <- form.field("username", form.parse_string)
    use password <- form.field("password", form.parse_string)
    form.success(LoginData(username:, password:))
  })
}

pub type LoginData {
  LoginData(username: String, password: String)
}

pub fn login_view(model: LoginModel) -> Element(LoginMsg) {
  let LoginModel(form) = model

  let handle_submit = fn(values) {
    form
    |> form.add_values(values)
    |> form.run
    |> UserSubmittedLogin
  }

  html.form([event.on_submit(handle_submit)], [
    view_input(form, is: "text", name: "username", label: "Username"),
    view_input(form, is: "password", name: "password", label: "Password"),
    html.button([], [html.text("Login")]),
  ])
}

pub type LoginModel {
  LoginModel(Form(LoginData))
}

pub type LoginMsg {
  UserSubmittedLogin(Result(LoginData, Form(LoginData)))
}

pub type LoginUpdateResultModel {
  LoginStayModel(LoginModel)
  LoginSuccessModel(String, Role)
}

pub fn login_init(_) -> LoginModel {
  LoginModel(new_login_form())
}

pub fn login_update(_model: LoginModel, msg: LoginMsg) -> LoginUpdateResultModel {
  case msg {
    UserSubmittedLogin(Ok(LoginData(username, _password))) ->
      LoginSuccessModel(username, SalesIntakeRole)

    UserSubmittedLogin(Error(form)) -> LoginStayModel(LoginModel(form))
  }
}
