import common.{
  type Role, DeliveryRole, ManagerRole, PurchaseRole, ReceiveRole,
  SalesIntakeRole, SalesPersonRole, role_to_string,
}
import gleam/dynamic/decode
import gleam/json

pub type Session {
  Session(id: Int, username: String, role: Role)
}

pub fn authenticate(
  username: String,
  password: String,
) -> Result(#(Role, Int), Nil) {
  case username, password {
    "manager", "manager" -> Ok(#(ManagerRole, 0))
    "sales_intake", "sales_intake" -> Ok(#(SalesIntakeRole, 1))
    "purchase", "purchase" -> Ok(#(PurchaseRole, 2))
    "receive", "receive" -> Ok(#(ReceiveRole, 3))
    "delivery", "delivery" -> Ok(#(DeliveryRole, 4))
    "sales_person", "sales_person" -> Ok(#(SalesPersonRole, 5))
    _, _ -> Error(Nil)
  }
}

pub fn encode_session(session: Session) -> String {
  json.object([
    #("id", json.int(session.id)),
    #("username", json.string(session.username)),
    #("role", json.string(role_to_string(session.role))),
  ])
  |> json.to_string
}

pub fn session_decoder() -> decode.Decoder(Session) {
  use id <- decode.field("id", decode.int)
  use username <- decode.field("username", decode.string)

  use role <- decode.field(
    "role",
    decode.string
      |> decode.then(fn(role_string) {
        case common.parse_role(role_string) {
          Ok(role) -> decode.success(role)
          Error(Nil) -> decode.failure(SalesIntakeRole, expected: "Role")
        }
      }),
  )

  decode.success(Session(id:, username:, role:))
}

pub type Authenticated

pub type Unauthenticated
