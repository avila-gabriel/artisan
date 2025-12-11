import formal/form.{type Form}
import gleam/int
import gleam/list
import gleam/string
import lustre
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import lustre/event

// =======================
// MAIN
// =======================

pub fn main() {
  let app = lustre.simple(init, update, view)
  let assert Ok(_) = lustre.start(app, "#app", Nil)
  Nil
}

// =======================
// ROOT MODEL / MSG
// =======================

type AppModel {
  LoginPageModel(LoginModel)
  SalesIntakePageModel(SalesIntakeModel)
}

type AppMsg {
  LoginPageMsg(LoginMsg)
  SalesIntakePageMsg(SalesIntakeMsg)
}

fn init(_) -> AppModel {
  LoginPageModel(login_init(Nil))
}

fn update(model: AppModel, msg: AppMsg) -> AppModel {
  case msg {
    LoginPageMsg(login_msg) -> {
      case model {
        LoginPageModel(login_model) -> {
          case login_update(login_model, login_msg) {
            LoginStayModel(updated) -> LoginPageModel(updated)

            LoginSuccessModel(username, role) -> {
              case role {
                SalesIntake -> SalesIntakePageModel(sales_init(username))

                Purchase -> todo

                Receive -> todo

                Delivery -> todo

                SalesPerson -> todo

                Manager -> todo
              }
            }
          }
        }

        _ -> model
      }
    }

    SalesIntakePageMsg(sales_msg) -> {
      case model {
        SalesIntakePageModel(m) ->
          SalesIntakePageModel(sales_update(m, sales_msg))

        _ -> model
      }
    }
  }
}

fn view(model: AppModel) -> Element(AppMsg) {
  html.div(
    [attribute.class("p-32 mx-auto w-full max-w-2xl space-y-4")],
    case model {
      LoginPageModel(m) -> [login_view(m) |> element.map(LoginPageMsg)]

      SalesIntakePageModel(m) -> [
        sales_view(m) |> element.map(SalesIntakePageMsg),
      ]
    },
  )
}

// =======================
// LOGIN APP
// =======================

type LoginModel {
  LoginModel(Form(LoginData))
}

type LoginMsg {
  UserSubmittedLogin(Result(LoginData, Form(LoginData)))
}

type LoginUpdateResultModel {
  LoginStayModel(LoginModel)
  LoginSuccessModel(String, Role)
}

fn login_init(_) -> LoginModel {
  LoginModel(new_login_form())
}

fn login_update(model: LoginModel, msg: LoginMsg) -> LoginUpdateResultModel {
  let LoginModel(form) = model

  case msg {
    UserSubmittedLogin(Ok(LoginData(username:, password:))) -> {
      case authenticate(username, password) {
        Ok(role) -> LoginSuccessModel(username, role)

        Error(_) -> panic as "db error?"
      }
    }

    UserSubmittedLogin(Error(form)) -> LoginStayModel(LoginModel(form))
  }
}

fn login_view(model: LoginModel) -> Element(LoginMsg) {
  let LoginModel(form) = model

  let handle_submit = fn(values) {
    form
    |> form.add_values(values)
    |> form.run
    |> UserSubmittedLogin
  }

  html.form(
    [
      attribute.class("p-8 w-full border rounded-2xl shadow-lg space-y-4"),
      event.on_submit(handle_submit),
    ],
    [
      html.h1([attribute.class("text-2xl font-medium text-purple-600")], [
        html.text("Sign in"),
      ]),
      view_input(form, is: "text", name: "username", label: "Username"),
      view_input(form, is: "password", name: "password", label: "Password"),
      html.div([attribute.class("flex justify-end")], [
        html.button(
          [
            attribute.class("text-white text-sm font-bold"),
            attribute.class("px-4 py-2 bg-purple-600 rounded-lg"),
          ],
          [html.text("Login")],
        ),
      ]),
    ],
  )
}

// =======================
// SALES INTAKE APP
// =======================

type SalesIntakeModel {
  SalesIntakeModel(
    username: String,
    products: List(Product),
    form: Form(ImportedSale),
  )
}

type SalesIntakeMsg {
  ImportedSaleSubmitted(Result(ImportedSale, Form(ImportedSale)))
}

fn sales_init(username: String) -> SalesIntakeModel {
  SalesIntakeModel(username, [], new_imported_sale_form())
}

fn sales_update(
  model: SalesIntakeModel,
  msg: SalesIntakeMsg,
) -> SalesIntakeModel {
  let SalesIntakeModel(username, products, form) = model

  case msg {
    ImportedSaleSubmitted(Ok(ImportedSale(raw))) -> {
      let products = map_products(raw)
      SalesIntakeModel(username, products, form)
    }

    ImportedSaleSubmitted(Error(form)) ->
      SalesIntakeModel(username, products, form)
  }
}

fn sales_view(model: SalesIntakeModel) -> Element(SalesIntakeMsg) {
  let SalesIntakeModel(_, products, form) = model

  let handle_submit = fn(values) {
    form
    |> form.add_values(values)
    |> form.run
    |> ImportedSaleSubmitted
  }

  html.div([], [
    products_table(products),
    html.form([event.on_submit(handle_submit)], [
      view_input(
        form,
        is: "file",
        name: "imported_sale",
        label: "Imported Sale",
      ),
      html.button([], [html.text("Import Sale")]),
    ]),
  ])
}

// =======================
// SHARED TYPES / HELPERS
// =======================

pub type ImportedSale {
  ImportedSale(imported_sale: String)
}

pub type Product {
  Product(nome: String, ambiente: String, quantidade: Int)
}

type LoginData {
  LoginData(username: String, password: String)
}

pub type Role {
  SalesIntake
  Purchase
  Receive
  Delivery
  SalesPerson
  Manager
}

fn authenticate(username: String, password: String) -> Result(Role, Nil) {
  Ok(SalesIntake)
}

fn new_login_form() -> Form(LoginData) {
  form.new({
    use username <- form.field(
      "username",
      form.parse_string
        |> form.map(string.trim)
        |> form.check_not_empty
        |> form.check_string_length_more_than(3)
        |> form.check_string_length_less_than(20),
    )

    use password <- form.field(
      "password",
      form.parse_string
        |> form.map(string.trim)
        |> form.check_string_length_less_than(14)
        |> form.check_string_length_more_than(3),
    )

    form.success(LoginData(username:, password:))
  })
}

fn new_imported_sale_form() -> Form(ImportedSale) {
  form.new({
    use imported_sale <- form.field(
      "imported_sale",
      form.parse_string
        |> form.map(string.trim)
        |> form.check(parse_products),
    )
    form.success(ImportedSale(imported_sale:))
  })
}

fn parse_products(string: String) -> Result(String, String) {
  todo
}

fn map_products(raw: String) -> List(Product) {
  todo
}

// =======================
// SHARED VIEWS
// =======================

fn products_table(products: List(Product)) -> Element(msg) {
  let header =
    html.tr([], [
      html.th([], [html.text("Nome")]),
      html.th([], [html.text("Ambiente")]),
      html.th([], [html.text("Quantidade")]),
    ])

  let rows =
    list.map(products, fn(product) {
      let Product(nome:, ambiente:, quantidade:) = product

      html.tr([], [
        html.td([], [html.text(nome)]),
        html.td([], [html.text(ambiente)]),
        html.td([], [html.text(int.to_string(quantidade))]),
      ])
    })

  html.table([], [header, ..rows])
}

fn view_input(
  form: Form(data),
  is type_: String,
  name name: String,
  label label: String,
) -> Element(msg) {
  let errors = form.field_error_messages(form, name)

  html.div([], [
    html.label(
      [attribute.for(name), attribute.class("text-xs font-bold text-slate-600")],
      [html.text(label)],
    ),
    html.input([
      attribute.type_(type_),
      attribute.name(name),
      attribute.id(name),
    ]),
    ..list.map(errors, fn(err) {
      html.p([attribute.class("text-red-500 text-xs")], [
        html.text(err),
      ])
    })
  ])
}
