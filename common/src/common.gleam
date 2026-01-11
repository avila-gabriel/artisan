import gleam/list
import gleam/option.{type Option, Some}
import gleam/string

pub type Role {
  SalesIntakeRole
  PurchaseRole
  ReceiveRole
  DeliveryRole
  SalesPersonRole
  ManagerRole
}

pub fn role_to_string(role: Role) -> String {
  case role {
    SalesIntakeRole -> "sales_intake"
    PurchaseRole -> "purchase"
    ReceiveRole -> "receive"
    DeliveryRole -> "delivery"
    SalesPersonRole -> "sales_person"
    ManagerRole -> "manager"
  }
}

pub fn role_from_string(role: String) -> Option(Role) {
  case role {
    "sales_intake" -> Some(SalesIntakeRole)
    "purchase" -> Some(PurchaseRole)
    "receive" -> Some(ReceiveRole)
    "delivery" -> Some(DeliveryRole)
    "sales_person" -> Some(SalesPersonRole)
    "manager" -> Some(ManagerRole)
    _ -> option.None
  }
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

pub fn validate_products(products: List(Product)) -> Option(List(String)) {
  case
    products
    |> list.map(validate_product)
    |> list.flatten
  {
    [] -> option.None
    errors -> Some(errors)
  }
}
