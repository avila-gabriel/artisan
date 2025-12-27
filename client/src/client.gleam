import common
import login
import lustre
import lustre/attribute
import lustre/effect
import lustre/element.{type Element}
import lustre/element/html
import roles/sales_intake

pub fn main() {
  let app = lustre.application(init, update, view)
  let assert Ok(_) = lustre.start(app, "#app", Nil)
}

pub type Model {
  LoginPageModel(login.LoginModel)
  SalesIntakePageModel(sales_intake.Model)
}

pub type Msg {
  Login(login.LoginMsg)
  SalesIntake(sales_intake.Msg)
}

pub fn init(_) -> #(Model, effect.Effect(Msg)) {
  #(LoginPageModel(login.login_init(Nil)), effect.none())
}

pub fn update(model: Model, msg: Msg) -> #(Model, effect.Effect(Msg)) {
  case model {
    LoginPageModel(login_model) ->
      case msg {
        Login(login_msg) ->
          case login.login_update(login_model, login_msg) {
            login.LoginStayModel(updated) -> #(
              LoginPageModel(updated),
              effect.none(),
            )

            login.LoginSuccessModel(username, role) ->
              case role {
                common.SalesIntakeRole -> #(
                  SalesIntakePageModel(sales_intake.init(username)),
                  effect.none(),
                )
                common.PurchaseRole -> #(
                  LoginPageModel(login_model),
                  effect.none(),
                )
                common.ReceiveRole -> #(
                  LoginPageModel(login_model),
                  effect.none(),
                )
                common.DeliveryRole -> #(
                  LoginPageModel(login_model),
                  effect.none(),
                )
                common.SalesPersonRole -> #(
                  LoginPageModel(login_model),
                  effect.none(),
                )
                common.ManagerRole -> #(
                  LoginPageModel(login_model),
                  effect.none(),
                )
              }
          }

        SalesIntake(_) -> #(LoginPageModel(login_model), effect.none())
      }

    SalesIntakePageModel(sales_model) ->
      case msg {
        SalesIntake(sales_msg) -> {
          let #(m2, eff) = sales_intake.update(sales_model, sales_msg)
          #(SalesIntakePageModel(m2), effect.map(eff, SalesIntake))
        }

        Login(_) -> #(SalesIntakePageModel(sales_model), effect.none())
      }
  }
}

pub fn view(model: Model) -> Element(Msg) {
  html.div(
    [attribute.class("p-32 mx-auto w-full max-w-2xl space-y-4")],
    case model {
      LoginPageModel(m) -> [login.login_view(m) |> element.map(Login)]

      SalesIntakePageModel(m) -> [
        sales_intake.view(m) |> element.map(SalesIntake),
      ]
    },
  )
}
