import formal/form.{type Form}
import gleam/list
import gleam/option
import gleam/string
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html

pub type Role {
  SalesIntakeRole
  PurchaseRole
  ReceiveRole
  DeliveryRole
  SalesPersonRole
  ManagerRole
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

pub type Product {
  Product(nome: String, ambiente: String, quantidade: Int)
}

pub fn validate_product(product: Product) -> List(String) {
  let Product(nome, ambiente, quantidade) = product

  let nome_errors = case string.trim(nome) == "" {
    True -> ["Nome do produto não pode ser vazio"]
    False -> []
  }

  let ambiente_errors = case string.trim(ambiente) == "" {
    True -> ["Ambiente não pode ser vazio"]
    False -> []
  }

  let quantidade_errors = case quantidade < 1 {
    True -> ["Quantidade deve ser maior que zero"]
    False -> []
  }

  list.append(nome_errors, ambiente_errors)
  |> list.append(quantidade_errors)
}

pub fn validate_products(products: List(Product)) -> option.Option(List(String)) {
  case
    products
    |> list.map(validate_product)
    |> list.flatten
  {
    [] -> option.None
    errors -> option.Some(errors)
  }
}
