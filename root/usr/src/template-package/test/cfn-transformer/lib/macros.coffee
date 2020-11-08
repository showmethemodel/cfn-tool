module.exports.init = (xform) ->
  xform.defmacro 'Fn::UpperCase', (form) -> form.toUpperCase()
