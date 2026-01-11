import formal/form.{type Form}
import gleam/javascript/promise
import gleam/list
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html

@external(javascript, "./file.ffi.mjs", "read_file_as_text")
pub fn read_file_as_text(
  input_id: String,
) -> promise.Promise(Result(String, String))

pub fn view_input(
  form: Form(data),
  is type_: String,
  name name: String,
  label label: String,
) -> Element(msg) {
  let errors = form.field_error_messages(form, name)

  html.div([], [
    html.label([attribute.for(name)], [html.text(label)]),
    html.input([
      attribute.type_(type_),
      attribute.name(name),
      attribute.id(name),
      attribute.value(form.field_value(form, name)),
      case errors {
        [] -> attribute.none()
        _ -> attribute.aria_invalid("true")
      },
    ]),
    ..list.map(errors, fn(err) { html.p([], [html.text(err)]) })
  ])
}
