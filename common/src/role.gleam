pub type Role {
  SalesIntakeRole
  PurchaseRole
  ReceiveRole
  DeliveryRole
  SalesPersonRole
  ManagerRole
}

pub fn to_string(role: Role) -> String {
  case role {
    SalesIntakeRole -> "sales_intake"
    PurchaseRole -> "purchase"
    ReceiveRole -> "receive"
    DeliveryRole -> "delivery"
    SalesPersonRole -> "sales_person"
    ManagerRole -> "manager"
  }
}

pub fn parse(role: String) -> Result(Role, Nil) {
  case role {
    "sales_intake" -> Ok(SalesIntakeRole)
    "purchase" -> Ok(PurchaseRole)
    "receive" -> Ok(ReceiveRole)
    "delivery" -> Ok(DeliveryRole)
    "sales_person" -> Ok(SalesPersonRole)
    "manager" -> Ok(ManagerRole)
    _ -> Error(Nil)
  }
}
