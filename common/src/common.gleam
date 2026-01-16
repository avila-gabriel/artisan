import gleam/list
import gleam/result
import gleam/string
import gleam/time/timestamp.{type Timestamp}

pub type Sale {
  Sale(
    products: List(Product1(Valid)),
    created_at: Timestamp,
    created_by: String,
  )
}

pub type Product1(validation) {
  Product(nome: String, ambiente: String, quantidade: Int)
}

pub type Product2 {
  Product2(child: Product1(Valid), supplier: Supplier(Valid), cost: Real)
}

pub type Product3 {
  Product3(child: Product2, received_at: Timestamp, status: ReceiveStatus)
}

pub type ReceiveStatus {
  Damaged
  Approved
}

pub type Product4 {
  Product4(child: Product3, delivered_at: Timestamp)
}

pub type Supplier(validation) {
  Supplier(String)
}

pub type Real {
  Real(reais: Int, centavos: Centavos(Valid))
}

pub type Centavos(validation) {
  Centavos(Int)
}

pub type Valid

pub type Invalid

pub type Purchase {
  Purchase(sale: Sale)
}

pub fn parse_product(
  product: Product1(Invalid),
) -> Result(Product1(Valid), List(String)) {
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

  case
    list.append(nome_errors, ambiente_errors)
    |> list.append(quantidade_errors)
  {
    [] -> {
      let product: Product1(Valid) = Product(nome:, ambiente:, quantidade:)
      Ok(product)
    }
    errors -> Error(errors)
  }
}

pub fn validate_products(
  products: List(Product1(Invalid)),
) -> Result(List(Product1(Valid)), List(String)) {
  products
  |> list.map(parse_product)
  |> result.all
  |> result.map(fn(products) {
    list.map(products, fn(product) {
      let product: Product1(Valid) = Product(..product)
      product
    })
  })
}
