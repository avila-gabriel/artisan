import formal/form.{type Form}
import gleam/dict
import gleam/int
import gleam/javascript/promise
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
import shared.{view_input}

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
    view_input(form, is: "text", name: "fornecedor", label: "Fornecedor"),
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
    supplier_form: Form(SupplierData),
    supplier: Option(String),
  )
}

pub type SalesIntakeMsg {
  ReadFile
  FileRead(Result(String, String))
  UserSubmittedSupplier(Result(SupplierData, Form(SupplierData)))
  UpdateProduct(Product)
}

pub fn sales_intake_init(username: String) -> SalesIntakeModel {
  SalesIntakeModel(
    username,
    [Product(0, "", "", 1)],
    "No file loaded",
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
  }
}

pub fn sales_intake_view(model: SalesIntakeModel) -> Element(SalesIntakeMsg) {
  let SalesIntakeModel(username, products, status, supplier_form, supplier) =
    model

  html.div([], [
    html.p([], [html.text("Bem-Vindo " <> username)]),
    html.p([], [html.text(status)]),
    supplier_view(supplier_form, supplier),
    products_view(products),
    html.input([
      attribute.type_("file"),
      attribute.id("imported-sale"),
      attribute.accept([".csv", "text/csv"]),
    ]),
    html.button([event.on_click(ReadFile)], [html.text("Import Sale")]),
    exportacao_sistema_atual(),
  ])
}

pub fn products_view(products: List(Product)) -> Element(SalesIntakeMsg) {
  html.table([attribute.class("w-full border-collapse")], [
    html.thead([], [
      html.tr([], [
        html.th([], [html.text("Nome")]),
        html.th([], [html.text("Ambiente")]),
        html.th([], [html.text("Quantidade")]),
      ]),
    ]),
    keyed.tbody(
      [],
      list.map(products, fn(product) {
        #(int.to_string(product.id), product_row(product))
      }),
    ),
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
  Product(id: Int, nome: String, ambiente: String, quantidade: Int)
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
