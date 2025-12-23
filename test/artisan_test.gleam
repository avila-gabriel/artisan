import gleam/uri
import gleeunit
import roles/sales_intake
import shared

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn happy_path_parse_csv_test() {
  let raw =
    "nome,ambiente,quantidade
    a,b,1"
  assert sales_intake.parse_csv(raw) == Ok(raw)
}

pub fn url_safe_parse_test() {
  assert shared.url |> uri.parse != Error(Nil)
}
