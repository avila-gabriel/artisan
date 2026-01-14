import common.{type Product, Product}
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option
import gleam/time/timestamp
import server/auth
import server/db
import server/sql
import server/web.{type Context}
import sqlight
import wisp.{type Request, type Response}

pub type RegisterInput {
  RegisterInput(supplier: String, products: List(Product))
}

fn register_decoder() -> decode.Decoder(RegisterInput) {
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

  decode.success(RegisterInput(supplier:, products:))
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

pub fn register(req: Request, ctx: Context(auth.Authenticated)) -> Response {
  use json <- wisp.require_json(req)

  case decode.run(json, register_decoder()) {
    Error(_) -> wisp.unprocessable_content()

    Ok(RegisterInput(supplier, products)) ->
      case common.validate_products(products) {
        option.Some(_) -> wisp.unprocessable_content()

        option.None -> {
          let now =
            timestamp.system_time()
            |> timestamp.to_unix_seconds

          case register_db(ctx, supplier, products, now) {
            Ok(_) -> wisp.created()
            Error(e) -> {
              echo e
              wisp.internal_server_error()
            }
          }
        }
      }
  }
}

pub fn register_db(
  ctx: Context(auth.Authenticated),
  supplier: String,
  products: List(Product),
  now: Float,
) -> Result(Int, sqlight.Error) {
  db.with_transaction(ctx.db, 5000, 5000, fn(conn) {
    let #(sql1, params1, decoder1) =
      sql.create_sales_intake(web.get_session(ctx).username, supplier, now)

    case
      sqlight.query(
        sql1,
        on: conn,
        with: list.map(params1, db.parrot_to_sqlight),
        expecting: decoder1,
      )
    {
      Error(e) -> Error(e)

      Ok(rows) ->
        case rows {
          [sql.CreateSalesIntake(id:), ..] ->
            case insert_products(conn, id, products) {
              Ok(Nil) -> Ok(id)
              Error(e) -> Error(e)
            }

          _ ->
            Error(sqlight.SqlightError(
              code: sqlight.GenericError,
              message: "Expected CreateSalesIntake to return one row with id",
              offset: -1,
            ))
        }
    }
  })
}
