import formal/form.{type Form}
import gleam/dict
import gleam/int
import gleam/javascript/promise
import gleam/list
import gleam/option.{type Option, None, Some}
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
    UserSubmittedLogin(Ok(LoginData(username, _password))) ->
      LoginSuccessModel(username, SalesIntakeRole)

    UserSubmittedLogin(Error(form)) -> LoginStayModel(LoginModel(form))
  }
}

pub fn supplier_view(form: Form(SupplierData)) {
  let handle_submit = fn(values) {
    form
    |> form.add_values(values)
    |> form.run
    |> UserSubmittedSupplier
  }

  html.form([event.on_submit(handle_submit)], [
    view_input(form, is: "text", name: "fornecedor", label: "Fornecedor"),
    html.button([], [html.text("Fornecedor")]),
  ])
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
  SalesIntakeModel(
    username: String,
    products: List(Product),
    status: String,
    supplier_form: Form(SupplierData),
    supplier: Option(String),
  )
}

pub type SalesIntakeMsg {
  ReadFile
  FileRead(Result(String, String))
  UserSubmittedSupplier(Result(SupplierData, Form(SupplierData)))
}

pub fn sales_intake_init(username: String) -> SalesIntakeModel {
  SalesIntakeModel(username, [], "No file loaded", new_supplier_form(), None)
}

pub fn sales_intake_update(
  model: SalesIntakeModel,
  msg: SalesIntakeMsg,
) -> #(SalesIntakeModel, effect.Effect(SalesIntakeMsg)) {
  case msg {
    ReadFile -> #(
      SalesIntakeModel(..model, status: "Reading file…"),
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
          SalesIntakeModel(
            ..model,
            products: map_products(text),
            status: "File loaded",
          ),
          effect.none(),
        )

        Error(_) -> #(
          SalesIntakeModel(..model, status: "Invalid CSV"),
          effect.none(),
        )
      }

    FileRead(Error(_)) -> #(
      SalesIntakeModel(..model, status: "Failed to read file"),
      effect.none(),
    )
    UserSubmittedSupplier(Ok(SupplierData(supplier:))) -> #(
      SalesIntakeModel(..model, supplier: Some(supplier)),
      effect.none(),
    )

    UserSubmittedSupplier(Error(form)) -> #(
      SalesIntakeModel(..model, supplier_form: form),
      effect.none(),
    )
  }
}

pub fn sales_intake_view(model: SalesIntakeModel) -> Element(SalesIntakeMsg) {
  let SalesIntakeModel(username, products, status, supplier_form, _supplier) =
    model

  html.div([], [
    html.p([], [html.text("Bem-Vindo " <> username)]),
    html.p([], [html.text(status)]),
    supplier_view(supplier_form),
    products_table(products),
    html.input([
      attribute.type_("file"),
      attribute.id("imported-sale"),
    ]),
    html.button([event.on_click(ReadFile)], [html.text("Import Sale")]),
    exportacao_sistema_atual(),
  ])
}

pub fn exportacao_sistema_atual() {
  html.div(
    [
      attribute.class(
        "max-w-3xl mx-auto bg-white border border-gray-200 rounded-xl shadow-sm p-6",
      ),
    ],
    [
      html.div(
        [
          attribute.class("flex items-start gap-4"),
        ],
        [
          html.div(
            [
              attribute.class(
                "flex-shrink-0 w-10 h-10 rounded-full bg-blue-100 text-blue-600 flex items-center justify-center font-semibold",
              ),
            ],
            [html.text("1")],
          ),

          html.div([], [
            html.h2(
              [
                attribute.class("text-lg font-semibold text-gray-900"),
              ],
              [html.text("Exportação do orçamento no sistema atual")],
            ),

            html.ol(
              [
                attribute.class(
                  "mt-4 space-y-2 text-sm text-gray-700 list-decimal list-inside",
                ),
              ],
              [
                html.li([], [html.text("Acessar Lista de Orçamentos")]),
                html.li([], [html.text("Selecionar o orçamento fechado")]),
                html.li([], [html.text("Clicar em Enviar")]),
                html.li([], [html.text("Salvar arquivo em Excel (XLS)")]),
                html.li([], [html.text("Converter o arquivo para CSV")]),
                html.li([], [html.text("Importar o CSV no novo sistema")]),
              ],
            ),

            html.div(
              [
                attribute.class(
                  "mt-4 rounded-lg bg-gray-50 border border-gray-200 p-4 text-sm text-gray-700",
                ),
              ],
              [
                html.ul(
                  [
                    attribute.class("list-disc list-inside space-y-1"),
                  ],
                  [
                    html.li([], [
                      html.text("Cada arquivo representa uma venda (orçamento)"),
                    ]),
                    html.li([], [
                      html.text("Uma venda contém uma lista de produtos"),
                    ]),
                    html.li([], [
                      html.text("Produtos incluem quantidade e ambiente"),
                    ]),
                    html.li([], [
                      html.text(
                        "O fornecedor não vem no arquivo e será informado depois",
                      ),
                    ]),
                  ],
                ),
              ],
            ),
          ]),
        ],
      ),
    ],
  )
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

pub type SupplierData {
  SupplierData(supplier: String)
}

pub fn new_supplier_form() -> Form(SupplierData) {
  form.new({
    use supplier <- form.field("supplier", form.parse_string)
    form.success(SupplierData(supplier:))
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
