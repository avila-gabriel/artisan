import formal/form.{type Form}
import gleam/dict
import gleam/int
import gleam/javascript/promise
import gleam/list
import gleam/result
import gsv
import lustre
import lustre/attribute
import lustre/effect
import lustre/element.{type Element}
import lustre/element/html
import lustre/event

@external(javascript, "./file.ffi.mjs", "read_file_as_text")
pub fn read_file_as_text(
  input_id: String,
) -> promise.Promise(Result(String, String))

pub fn main() {
  let app = lustre.application(init, update, view)
  let assert Ok(_) = lustre.start(app, "#app", Nil)
}

pub type AppModel {
  LoginPageModel(LoginModel)
  SalesIntakePageModel(SalesIntakeModel)
}

pub type AppMsg {
  Login(LoginMsg)
  SalesIntake(SalesIntakeMsg)
}

pub fn init(_) -> #(AppModel, effect.Effect(AppMsg)) {
  #(LoginPageModel(login_init(Nil)), effect.none())
}

pub fn update(
  model: AppModel,
  msg: AppMsg,
) -> #(AppModel, effect.Effect(AppMsg)) {
  case model {
    LoginPageModel(login_model) ->
      case msg {
        Login(login_msg) ->
          case login_update(login_model, login_msg) {
            LoginStayModel(updated) -> #(LoginPageModel(updated), effect.none())

            LoginSuccessModel(username, role) ->
              case role {
                SalesIntakeRole -> #(
                  SalesIntakePageModel(sales_intake_init(username)),
                  effect.none(),
                )
                PurchaseRole -> #(LoginPageModel(login_model), effect.none())
                ReceiveRole -> #(LoginPageModel(login_model), effect.none())
                DeliveryRole -> #(LoginPageModel(login_model), effect.none())
                SalesPersonRole -> #(LoginPageModel(login_model), effect.none())
                ManagerRole -> #(LoginPageModel(login_model), effect.none())
              }
          }

        SalesIntake(_) -> #(LoginPageModel(login_model), effect.none())
      }

    SalesIntakePageModel(sales_model) ->
      case msg {
        SalesIntake(sales_msg) -> {
          let #(m2, eff) = sales_intake_update(sales_model, sales_msg)
          #(SalesIntakePageModel(m2), effect.map(eff, SalesIntake))
        }

        Login(_) -> #(SalesIntakePageModel(sales_model), effect.none())
      }
  }
}

pub fn view(model: AppModel) -> Element(AppMsg) {
  html.div(
    [attribute.class("p-32 mx-auto w-full max-w-2xl space-y-4")],
    case model {
      LoginPageModel(m) -> [login_view(m) |> element.map(Login)]

      SalesIntakePageModel(m) -> [
        sales_intake_view(m) |> element.map(SalesIntake),
      ]
    },
  )
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
    UserSubmittedLogin(Ok(LoginData(username:, password:))) ->
      LoginSuccessModel(username, SalesIntakeRole)

    UserSubmittedLogin(Error(form)) -> LoginStayModel(LoginModel(form))
  }
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

pub type SalesIntakeModel {
  SalesIntakeModel(username: String, products: List(Product), status: String)
}

pub type SalesIntakeMsg {
  ReadFile
  FileRead(Result(String, String))
}

pub fn sales_intake_init(username: String) -> SalesIntakeModel {
  SalesIntakeModel(username, [], "No file loaded")
}

pub fn sales_intake_update(
  model: SalesIntakeModel,
  msg: SalesIntakeMsg,
) -> #(SalesIntakeModel, effect.Effect(SalesIntakeMsg)) {
  let SalesIntakeModel(username, products, _) = model

  case msg {
    ReadFile -> #(
      SalesIntakeModel(username, products, "Reading file…"),
      effect.from(fn(dispatch) {
        let _ =
          promise.await(read_file_as_text("imported-sale"), fn(result) {
            promise.resolve(dispatch(FileRead(result)))
          })
        Nil
      }),
    )

    FileRead(Ok(text)) ->
      case gsv.to_dicts(text, ",") {
        Ok(_) -> #(
          SalesIntakeModel(username, map_products(text), "File loaded"),
          effect.none(),
        )

        Error(_) -> #(
          SalesIntakeModel(username, [], "Invalid CSV"),
          effect.none(),
        )
      }

    FileRead(Error(_)) -> #(
      SalesIntakeModel(username, [], "Failed to read file"),
      effect.none(),
    )
  }
}

pub fn sales_intake_view(model: SalesIntakeModel) -> Element(SalesIntakeMsg) {
  let SalesIntakeModel(_, products, status) = model

  html.div([], [
    html.p([], [html.text(status)]),
    products_table(products),
    html.input([
      attribute.type_("file"),
      attribute.id("imported-sale"),
    ]),
    html.button([event.on_click(ReadFile)], [html.text("Import Sale")]),
  ])
}

pub type Product {
  Product(nome: String, ambiente: String, quantidade: Int)
}

pub type LoginData {
  LoginData(username: String, password: String)
}

pub type Role {
  SalesIntakeRole
  PurchaseRole
  ReceiveRole
  DeliveryRole
  SalesPersonRole
  ManagerRole
}

pub fn new_login_form() -> Form(LoginData) {
  form.new({
    use username <- form.field("username", form.parse_string)
    use password <- form.field("password", form.parse_string)
    form.success(LoginData(username:, password:))
  })
}

pub fn map_products(raw: String) -> List(Product) {
  gsv.to_dicts(raw, ",")
  |> result.unwrap([])
  |> list.map(fn(row) {
    Product(
      nome: dict.get(row, "nome") |> result.unwrap(""),
      ambiente: dict.get(row, "ambiente") |> result.unwrap(""),
      quantidade: dict.get(row, "quantidade")
        |> result.unwrap("0")
        |> int.parse
        |> result.unwrap(0),
    )
  })
}

pub fn products_table(products: List(Product)) -> Element(msg) {
  html.table(
    [],
    list.map(products, fn(p) {
      html.tr([], [
        html.td([], [html.text(p.nome)]),
        html.td([], [html.text(p.ambiente)]),
        html.td([], [html.text(int.to_string(p.quantidade))]),
      ])
    }),
  )
}

pub fn view_input(
  form: Form(data),
  is type_: String,
  name name: String,
  label label: String,
) -> Element(msg) {
  let errors = form.field_error_messages(form, name)

  html.div([], [
    html.label([attribute.for(name)], [html.text(label)]),
    html.input([
      attribute.type_(type_),
      attribute.name(name),
      attribute.id(name),
      attribute.value(form.field_value(form, name)),
      case errors {
        [] -> attribute.none()
        _ -> attribute.aria_invalid("true")
      },
    ]),
    ..list.map(errors, fn(err) { html.p([], [html.text(err)]) })
  ])
}
