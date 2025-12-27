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
import shared.{type Product, Product, validate_products, view_input}

@external(javascript, "../file.ffi.mjs", "read_file_as_text")
pub fn read_file_as_text(
  input_id: String,
) -> promise.Promise(Result(String, String))

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

pub type SalesIntakeModel {
  SalesIntakeModel(
    username: String,
    products: List(Product),
    status: String,
    errors: List(String),
    supplier_form: Form(SupplierData),
    supplier: Option(String),
  )
}

pub type SalesIntakeMsg {
  ReadFile
  FileRead(Result(String, String))
  UserSubmittedSupplier(Result(SupplierData, Form(SupplierData)))
  UpdateProduct(Product)
  SubmitSalesIntake
  ApiSubmittedSale(Result(response.Response(String), rsvp.Error))
  AddProduct
  RemoveProduct(Int)
  ResetSalesIntake
}

pub fn sales_intake_init(username: String) -> SalesIntakeModel {
  SalesIntakeModel(
    username,
    [Product(0, "", "", 1)],
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
        |> list.index_fold(Ok(Nil), fn(acc, product, index) {
          case acc {
            Error(_) -> acc

            Ok(_) ->
              case
                required_fields
                |> list.all(fn(field) { dict.has_key(product, field) })
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

    FileRead(Ok(raw)) ->
      case parse_csv(raw) {
        Error(err) -> #(
          SalesIntakeModel(..model, status: "Falha ao importar: " <> err),
          effect.none(),
        )
        Ok(content) -> #(
          SalesIntakeModel(
            ..model,
            status: "csv importado com sucesso!",
            products: map_products(content),
          ),
          effect.none(),
        )
      }
    FileRead(Error(err)) -> #(
      SalesIntakeModel(..model, status: "Failed to read file: " <> err),
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
    UpdateProduct(updated) -> #(
      SalesIntakeModel(
        ..model,
        products: list.map(model.products, fn(p) {
          case p.id == updated.id {
            True -> updated
            False -> p
          }
        }),
      ),
      effect.none(),
    )
    ResetSalesIntake -> #(sales_intake_init(model.username), effect.none())
    SubmitSalesIntake ->
      case validate_submission(model) {
        Error(errors) -> #(
          SalesIntakeModel(..model, status: "", errors: errors),
          effect.none(),
        )

        Ok(valid_model) -> #(
          SalesIntakeModel(..valid_model, status: "Enviando venda…", errors: []),
          submit_sale(model: valid_model),
        )
      }
    AddProduct -> {
      let id = next_product_id(model.products)

      #(
        SalesIntakeModel(
          ..model,
          products: list.append(model.products, [Product(id, "", "", 1)]),
        ),
        effect.none(),
      )
    }

    RemoveProduct(id) -> #(
      SalesIntakeModel(
        ..model,
        products: list.filter(model.products, fn(p) { p.id != id }),
      ),
      effect.none(),
    )

    ApiSubmittedSale(Ok(_)) -> #(
      SalesIntakeModel(
        ..model,
        status: "Venda registrada com sucesso",
        errors: [],
      ),
      effect.none(),
    )

    ApiSubmittedSale(Error(_)) -> #(
      SalesIntakeModel(
        ..model,
        status: "Erro ao registrar venda por parte do servidor",
        errors: [],
      ),
      effect.none(),
    )
  }
}

fn submit_sale(model model: SalesIntakeModel) -> effect.Effect(SalesIntakeMsg) {
  let assert SalesIntakeModel(username, products, _, _, _, Some(supplier)) =
    model

  let body =
    json.object([
      #("username", json.string(username)),
      #("supplier", json.string(supplier)),
      #(
        "products",
        json.array(from: products, of: fn(product) {
          let Product(_, nome, ambiente, quantidade) = product

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

fn validate_submission(
  model: SalesIntakeModel,
) -> Result(SalesIntakeModel, List(String)) {
  let SalesIntakeModel(_, products, _, _, _, supplier) = model

  let supplier_errors = case supplier {
    None -> ["Fornecedor é obrigatório"]
    Some(_) -> []
  }

  let product_presence_errors = case products {
    [] -> ["Não é possível registrar venda sem produtos"]
    _ -> []
  }

  let domain_errors = case products {
    [] -> []
    _ -> validate_products(products)
  }

  let errors =
    list.append(supplier_errors, product_presence_errors)
    |> list.append(domain_errors)

  case errors {
    [] -> Ok(model)
    _ -> Error(errors)
  }
}

pub fn sales_intake_view(model: SalesIntakeModel) -> Element(SalesIntakeMsg) {
  let SalesIntakeModel(
    username,
    products,
    status,
    errors,
    supplier_form,
    supplier,
  ) = model

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

pub fn products_view(products: List(Product)) -> Element(SalesIntakeMsg) {
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
      keyed.tbody(
        [],
        list.map(products, fn(product) {
          #(int.to_string(product.id), product_row(product))
        }),
      ),
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

fn product_row(product: Product) -> Element(SalesIntakeMsg) {
  let Product(id, nome, ambiente, quantidade) = product

  html.tr([], [
    html.td([], [
      html.input([
        attribute.type_("text"),
        attribute.value(nome),
        event.on_input(fn(v) {
          UpdateProduct(Product(id, v, ambiente, quantidade))
        }),
      ]),
    ]),
    html.td([], [
      html.input([
        attribute.type_("text"),
        attribute.value(ambiente),
        event.on_input(fn(v) { UpdateProduct(Product(id, nome, v, quantidade)) }),
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

          UpdateProduct(Product(id, nome, ambiente, q))
        }),
      ]),
    ]),
    html.td([], [
      html.button(
        [
          attribute.class("text-red-600"),
          event.on_click(RemoveProduct(id)),
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

pub type SupplierData {
  SupplierData(supplier: String)
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

pub fn map_products(raw: String) -> List(Product) {
  gsv.to_dicts(raw, ",")
  |> result.unwrap([])
  |> list.map_fold(-1, fn(counter, row) {
    let counter = counter + 1
    #(
      counter,
      Product(
        id: counter,
        nome: dict.get(row, "nome") |> result.unwrap(""),
        ambiente: dict.get(row, "ambiente") |> result.unwrap(""),
        quantidade: dict.get(row, "quantidade")
          |> result.unwrap("1")
          |> int.parse
          |> result.unwrap(1),
      ),
    )
  })
  |> pair.second
}

fn next_product_id(products: List(Product)) -> Int {
  products
  |> list.map(fn(p) { p.id })
  |> list.max(int.compare)
  |> result.unwrap(-1)
  |> fn(id) { id + 1 }
}
