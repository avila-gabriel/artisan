import gleam/list
import gleam/option
import gleam/string

pub type Role {
  SalesIntakeRole
  PurchaseRole
  ReceiveRole
  DeliveryRole
  SalesPersonRole
  ManagerRole
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
