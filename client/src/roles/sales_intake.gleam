import common.{type Product, Product, validate_products}
import formal/form.{type Form}
import gleam/dict
import gleam/http/response
import gleam/int
import gleam/javascript/promise
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/pair
import gleam/result
import gleam/string
import gsv
import lustre/attribute
import lustre/effect
import lustre/element.{type Element}
import lustre/element/html
import lustre/element/keyed
import lustre/event
import rsvp
import shared.{view_input}

@external(javascript, "../file.ffi.mjs", "read_file_as_text")
pub fn read_file_as_text(
  input_id: String,
) -> promise.Promise(Result(String, String))

pub type UiProduct {
  UiProduct(key: String, product: Product)
}

pub type SupplierData {
  SupplierData(supplier: String)
}

pub fn supplier_view(form: Form(SupplierData), supplier: Option(String)) {
  let handle_submit = fn(values) {
    form
    |> form.add_values(values)
    |> form.run
    |> UserSubmittedSupplier
  }

  html.form([event.on_submit(handle_submit)], [
    view_input(form, is: "text", name: "supplier", label: "Fornecedor"),
    html.button([], [html.text("Fornecedor")]),
    html.span([], [
      html.text(case supplier {
        Some(supplier) -> supplier
        None -> "Nenhum fornecedor fornecido"
      }),
    ]),
  ])
}

fn csv_error_message(error: gsv.Error) -> String {
  case error {
    gsv.UnescapedQuote(line) ->
      "Erro no CSV: aspas não escapadas na linha " <> int.to_string(line)

    gsv.MissingClosingQuote(starting_line) ->
      "Erro no CSV: aspas abertas sem fechamento (início na linha "
      <> int.to_string(starting_line)
      <> ")"
  }
}

pub type Model {
  Model(
    username: String,
    products: List(UiProduct),
    status: String,
    errors: List(String),
    supplier_form: Form(SupplierData),
    supplier: Option(String),
  )
}

pub type Msg {
  ReadFile
  FileRead(Result(String, String))
  UserSubmittedSupplier(Result(SupplierData, Form(SupplierData)))
  UpdateProduct(String, Product)
  SubmitSalesIntake
  ApiSubmittedSale(Result(response.Response(String), rsvp.Error))
  AddProduct
  RemoveProduct(String)
  ResetSalesIntake
}

pub fn init(username: String) -> Model {
  Model(
    username,
    [UiProduct("0", Product("", "", 1))],
    "",
    [],
    new_supplier_form(),
    None,
  )
}

pub fn parse_csv(raw: String) -> Result(String, String) {
  case gsv.to_dicts(raw, ",") {
    Error(err) -> Error(csv_error_message(err))
    Ok(csv) -> {
      let required_fields = ["nome", "ambiente", "quantidade"]

      let validation =
        csv
        |> list.index_fold(Ok(Nil), fn(acc, row, index) {
          case acc {
            Error(_) -> acc
            Ok(_) ->
              case
                required_fields
                |> list.all(fn(field) { dict.has_key(row, field) })
              {
                True -> Ok(Nil)
                False ->
                  Error(
                    "Linha "
                    <> int.to_string(index + 1)
                    <> " não contém todos os campos obrigatórios ("
                    <> string.join(required_fields, ", ")
                    <> ")",
                  )
              }
          }
        })

      case validation {
        Ok(_) -> Ok(raw)
        Error(msg) -> Error(msg)
      }
    }
  }
}

pub fn update(model: Model, msg: Msg) -> #(Model, effect.Effect(Msg)) {
  case msg {
    ReadFile -> #(
      Model(..model, status: "Reading file…"),
      effect.from(fn(dispatch) {
        let _ =
          promise.await(read_file_as_text("imported-sale"), fn(result) {
            promise.resolve(dispatch(FileRead(result)))
          })
        Nil
      }),
    )

    FileRead(Ok(raw)) ->
      case parse_csv(raw) {
        Error(err) -> #(
          Model(..model, status: "Falha ao importar: " <> err),
          effect.none(),
        )
        Ok(_) -> #(
          Model(
            ..model,
            status: "csv importado com sucesso!",
            products: map_products(raw),
          ),
          effect.none(),
        )
      }

    FileRead(Error(err)) -> #(
      Model(..model, status: "Failed to read file: " <> err),
      effect.none(),
    )

    UserSubmittedSupplier(Ok(SupplierData(supplier:))) -> #(
      Model(..model, supplier: Some(supplier)),
      effect.none(),
    )

    UserSubmittedSupplier(Error(form)) -> #(
      Model(..model, supplier_form: form),
      effect.none(),
    )

    UpdateProduct(key, updated) -> #(
      Model(
        ..model,
        products: list.map(model.products, fn(ui) {
          case ui.key == key {
            True -> UiProduct(key, updated)
            False -> ui
          }
        }),
      ),
      effect.none(),
    )

    ResetSalesIntake -> #(init(model.username), effect.none())

    SubmitSalesIntake ->
      case validate_submission(model) {
        Error(errors) -> #(
          Model(..model, status: "", errors: errors),
          effect.none(),
        )

        Ok(domain_products) -> #(
          Model(..model, status: "Enviando venda…", errors: []),
          submit_sale(model.username, domain_products, model.supplier),
        )
      }

    AddProduct -> {
      let key = int.to_string(list.length(model.products))

      #(
        Model(
          ..model,
          products: list.append(model.products, [
            UiProduct(key, Product("", "", 1)),
          ]),
        ),
        effect.none(),
      )
    }

    RemoveProduct(key) -> #(
      Model(
        ..model,
        products: list.filter(model.products, fn(p) { p.key != key }),
      ),
      effect.none(),
    )

    ApiSubmittedSale(Ok(_)) -> #(
      Model(..model, status: "Venda registrada com sucesso", errors: []),
      effect.none(),
    )

    ApiSubmittedSale(Error(_)) -> #(
      Model(
        ..model,
        status: "Erro ao registrar venda por parte do servidor",
        errors: [],
      ),
      effect.none(),
    )
  }
}

fn submit_sale(
  username: String,
  products: List(Product),
  supplier: Option(String),
) -> effect.Effect(Msg) {
  let assert Some(supplier) = supplier

  let body =
    json.object([
      #("username", json.string(username)),
      #("supplier", json.string(supplier)),
      #(
        "products",
        json.array(from: products, of: fn(product) {
          let Product(nome, ambiente, quantidade) = product
          json.object([
            #("nome", json.string(nome)),
            #("ambiente", json.string(ambiente)),
            #("quantidade", json.int(quantidade)),
          ])
        }),
      ),
    ])

  let handler = rsvp.expect_ok_response(ApiSubmittedSale)
  rsvp.post("/sales_intake", body, handler)
}

fn validate_submission(model: Model) -> Result(List(Product), List(String)) {
  let domain_products =
    model.products
    |> list.map(fn(ui) { ui.product })

  let supplier_errors = case model.supplier {
    None -> ["Fornecedor é obrigatório"]
    Some(_) -> []
  }

  let product_presence_errors = case domain_products {
    [] -> ["Não é possível registrar venda sem produtos"]
    _ -> []
  }

  let domain_errors =
    validate_products(domain_products)
    |> option.unwrap([])

  let errors =
    list.append(supplier_errors, product_presence_errors)
    |> list.append(domain_errors)

  case errors {
    [] -> Ok(domain_products)
    _ -> Error(errors)
  }
}

pub fn view(model: Model) -> Element(Msg) {
  let Model(username, products, status, errors, supplier_form, supplier) = model

  html.div([], [
    html.p([], [html.text("Bem-Vindo " <> username)]),
    html.p([], [html.text(status)]),
    html.ul(
      [attribute.class("text-red-600 list-disc list-inside")],
      list.map(errors, fn(err) { html.li([], [html.text(err)]) }),
    ),
    supplier_view(supplier_form, supplier),
    products_view(products),
    html.input([
      attribute.type_("file"),
      attribute.id("imported-sale"),
      attribute.accept([".csv", "text/csv"]),
    ]),
    html.button([event.on_click(ReadFile)], [html.text("Import Sale")]),
    exportacao_sistema_atual(),
    html.div([attribute.class("flex gap-4 mt-6")], [
      html.button(
        [
          attribute.class("px-4 py-2 bg-green-600 text-white rounded"),
          event.on_click(SubmitSalesIntake),
        ],
        [html.text("Registrar Venda")],
      ),
      html.button(
        [
          attribute.class("px-4 py-2 bg-gray-300 text-gray-800 rounded"),
          event.on_click(ResetSalesIntake),
        ],
        [html.text("Resetar")],
      ),
    ]),
  ])
}

pub fn products_view(products: List(UiProduct)) -> Element(Msg) {
  html.div([], [
    html.table([attribute.class("w-full border-collapse")], [
      html.thead([], [
        html.tr([], [
          html.th([], [html.text("Nome")]),
          html.th([], [html.text("Ambiente")]),
          html.th([], [html.text("Quantidade")]),
          html.th([], []),
        ]),
      ]),
      keyed.tbody([], list.map(products, fn(ui) { #(ui.key, product_row(ui)) })),
    ]),
    html.div([attribute.class("mt-2")], [
      html.button(
        [
          attribute.class("px-3 py-1 bg-blue-600 text-white rounded"),
          event.on_click(AddProduct),
        ],
        [html.text("+ Adicionar produto")],
      ),
    ]),
  ])
}

fn product_row(ui: UiProduct) -> Element(Msg) {
  let UiProduct(key, Product(nome, ambiente, quantidade)) = ui

  html.tr([], [
    html.td([], [
      html.input([
        attribute.type_("text"),
        attribute.value(nome),
        event.on_input(fn(v) {
          UpdateProduct(key, Product(v, ambiente, quantidade))
        }),
      ]),
    ]),
    html.td([], [
      html.input([
        attribute.type_("text"),
        attribute.value(ambiente),
        event.on_input(fn(v) {
          UpdateProduct(key, Product(nome, v, quantidade))
        }),
      ]),
    ]),
    html.td([], [
      html.input([
        attribute.type_("number"),
        attribute.value(int.to_string(quantidade)),
        event.on_input(fn(v) {
          let q =
            v
            |> int.parse
            |> result.unwrap(quantidade)

          UpdateProduct(key, Product(nome, ambiente, q))
        }),
      ]),
    ]),
    html.td([], [
      html.button(
        [
          attribute.class("text-red-600"),
          event.on_click(RemoveProduct(key)),
        ],
        [html.text("✕")],
      ),
    ]),
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
            html.h2([attribute.class("text-lg font-semibold text-gray-900")], [
              html.text("Exportação do orçamento no sistema atual"),
            ]),
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
          ]),
        ],
      ),
    ],
  )
}

pub fn new_supplier_form() -> Form(SupplierData) {
  form.new({
    use supplier <- form.field(
      "supplier",
      form.parse_string |> form.check_not_empty,
    )
    form.success(SupplierData(supplier:))
  })
}

pub fn map_products(raw: String) -> List(UiProduct) {
  gsv.to_dicts(raw, ",")
  |> result.unwrap([])
  |> list.map_fold(0, fn(counter, row) {
    let key = int.to_string(counter)

    #(
      counter + 1,
      UiProduct(
        key,
        Product(
          dict.get(row, "nome") |> result.unwrap(""),
          dict.get(row, "ambiente") |> result.unwrap(""),
          dict.get(row, "quantidade")
            |> result.unwrap("1")
            |> int.parse
            |> result.unwrap(1),
        ),
      ),
    )
  })
  |> pair.second
}
