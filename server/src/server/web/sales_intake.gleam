import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option
import gleam/time/timestamp
import server/db
import server/sql
import server/web.{type Context}
import shared.{type Product, Product}
import sqlight
import wisp.{type Request, type Response}

pub type RegisterInput {
  RegisterInput(username: String, supplier: String, products: List(Product))
}

fn register_decoder() -> decode.Decoder(RegisterInput) {
  use username <- decode.field("username", decode.string)
  use supplier <- decode.field("supplier", decode.string)

  use products <- decode.field(
    "products",
    decode.list({
      use nome <- decode.field("nome", decode.string)
      use ambiente <- decode.field("ambiente", decode.string)
      use quantidade <- decode.field("quantidade", decode.int)
      decode.success(Product(nome:, ambiente:, quantidade:))
    }),
  )

  decode.success(RegisterInput(username:, supplier:, products:))
}

fn nil_decoder() -> decode.Decoder(Nil) {
  decode.success(Nil)
}

fn insert_products(
  conn: sqlight.Connection,
  sale_id: Int,
  products: List(Product),
) -> Result(Nil, sqlight.Error) {
  case products {
    [] -> Ok(Nil)

    [Product(nome, ambiente, quantidade), ..rest] -> {
      let #(sql2, params2) =
        sql.add_sales_intake_product(sale_id, nome, ambiente, quantidade)

      case
        sqlight.query(
          sql2,
          on: conn,
          with: list.map(params2, db.parrot_to_sqlight),
          expecting: nil_decoder(),
        )
      {
        Error(e) -> Error(e)
        Ok(_) -> insert_products(conn, sale_id, rest)
      }
    }
  }
}

pub fn register(req: Request, ctx: Context) -> Response {
  use json <- wisp.require_json(req)

  case decode.run(json, register_decoder()) {
    Error(_) -> wisp.unprocessable_content()

    Ok(RegisterInput(username, supplier, products)) -> {
      case shared.validate_products(products) {
        option.Some(_) -> wisp.unprocessable_content()

        option.None -> {
          let now =
            timestamp.system_time()
            |> timestamp.to_unix_seconds

          case
            db.with_transaction(ctx.db, 5000, 5000, fn(conn) {
              let #(sql1, params1, decoder1) =
                sql.create_sales_intake(username, supplier, now)

              case
                sqlight.query(
                  sql1,
                  on: conn,
                  with: list.map(params1, db.parrot_to_sqlight),
                  expecting: decoder1,
                )
              {
                Error(e) -> Error(e)

                Ok(rows) -> {
                  case rows {
                    [sql.CreateSalesIntake(id:), ..] -> {
                      case insert_products(conn, id, products) {
                        Ok(_) -> Ok(id)
                        Error(e) -> Error(e)
                      }
                    }

                    _ ->
                      Error(sqlight.SqlightError(
                        code: sqlight.GenericError,
                        message: "Expected CreateSalesIntake to return one row with id",
                        offset: -1,
                      ))
                  }
                }
              }
            })
          {
            Ok(id) ->
              wisp.json_response(
                json.to_string(
                  json.object([
                    #("id", json.int(id)),
                  ]),
                ),
                201,
              )

            Error(_) -> wisp.internal_server_error()
          }
        }
      }
    }
  }
}
