import gleam/option.{None, Some}
import login
import lustre
import lustre/attribute
import lustre/effect
import lustre/element.{type Element}
import lustre/element/html
import roles/sales_intake
import shared

pub fn main() {
  let app = lustre.application(init, update, view)
  let assert Ok(_) = lustre.start(app, "#app", Nil)
}

pub type AppModel {
  LoginPageModel(login.LoginModel)
  SalesIntakePageModel(sales_intake.SalesIntakeModel)
}

pub type AppMsg {
  Login(login.LoginMsg)
  SalesIntake(sales_intake.SalesIntakeMsg)
}

pub fn init(_) -> #(AppModel, effect.Effect(AppMsg)) {
  #(LoginPageModel(login.login_init(Nil)), effect.none())
}

pub fn update(
  model: AppModel,
  msg: AppMsg,
) -> #(AppModel, effect.Effect(AppMsg)) {
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
                shared.SalesIntakeRole -> #(
                  SalesIntakePageModel(sales_intake.sales_intake_init(username)),
                  effect.none(),
                )
                shared.PurchaseRole -> #(
                  LoginPageModel(login_model),
                  effect.none(),
                )
                shared.ReceiveRole -> #(
                  LoginPageModel(login_model),
                  effect.none(),
                )
                shared.DeliveryRole -> #(
                  LoginPageModel(login_model),
                  effect.none(),
                )
                shared.SalesPersonRole -> #(
                  LoginPageModel(login_model),
                  effect.none(),
                )
                shared.ManagerRole -> #(
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
          let #(m2, eff) =
            sales_intake.sales_intake_update(sales_model, sales_msg)
          #(SalesIntakePageModel(m2), effect.map(eff, SalesIntake))
        }

        Login(_) -> #(SalesIntakePageModel(sales_model), effect.none())
      }
  }
}

pub fn view(model: AppModel) -> Element(AppMsg) {
  html.div(
    [attribute.class("p-32 mx-auto w-full max-w-2xl space-y-4")],
    case model {
      LoginPageModel(m) -> [login.login_view(m) |> element.map(Login)]

      SalesIntakePageModel(m) -> [
        sales_intake.sales_intake_view(m) |> element.map(SalesIntake),
      ]
    },
  )
}
