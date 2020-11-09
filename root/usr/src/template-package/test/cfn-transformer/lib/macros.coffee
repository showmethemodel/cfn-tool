module.exports = (xform) ->
  xform.defmacro 'UpperCase', (form) -> form.toUpperCase()
