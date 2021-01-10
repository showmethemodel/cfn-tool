yaml            = require 'js-yaml'
fs              = require 'fs'
os              = require 'os'
path            = require 'path'
assert          = require 'assert'
crypto          = require 'crypto'
{execSync}      = require 'child_process'
YamlTransformer = require './yaml-transformer'
{ResourceTypes} = require './schema/CloudFormationResourceSpecification.json'

topLevelResourceProperties = [
  'Type'
  'Condition'
  'CreationPolicy'
  'DeletionPolicy'
  'DependsOn'
  'Metadata'
  'UpdatePolicy'
  'UpdateReplacePolicy'
]

gensym = do (counter = 0) ->
  (prefix = 'gensym') -> "#{prefix}_#{counter++}"

execShell = (command, opts) ->
  try
    execSync(command, merge({stdio: 'pipe'}, opts))
  catch e
    msg = "shell exec failed: #{command}"
    err = e.stderr.toString('utf-8')
    assert.fail(if err? then "#{msg}\n#{err}" else msg)

readFile = (file) ->
  fs.readFileSync(file).toString('utf-8')

typeOf = (thing) ->
  Object::toString.call(thing)[8...-1]

fileExt = (file) ->
  if (e = split(path.basename(file), '.', 2)[1])? then ".#{e}"

merge = (args...) ->
  Object.assign.apply(null, args)

deepMerge = (args...) ->
  dm = (x, y) ->
    if not (isObject(x) and isObject(y))
      y
    else
      ret = Object.assign({}, x)
      ret[k] = dm(x[k], v) for k, v of y
      ret
  args.reduce(((xs, x) -> dm(xs, x)), {})

hashMap = (args...) ->
  ret = {}
  ret[args[2*i]] = args[2*i+1] for i in [0...args.length/2]
  ret

isDirectory = (file) ->
  fs.statSync(file).isDirectory()

md5 = (data) ->
  crypto.createHash("md5").update(data).digest("hex")

md5File = (filePath) ->
  md5(fs.readFileSync(filePath))

peek = (ary) -> ary[ary.length - 1]

getIn = (obj, ks) -> ks.reduce(((xs, x) -> xs[x]), obj)

split = (str, sep, count=Infinity) ->
  toks  = str.split(sep)
  n     = Math.min(toks.length, count) - 1
  toks[0...n].concat(toks[n..].join(sep))

isString  = (x) -> typeOf(x) is 'String'
isArray   = (x) -> typeOf(x) is 'Array'
isObject  = (x) -> typeOf(x) is 'Object'
isBoolean = (x) -> typeOf(x) is 'Boolean'

assertObject = (thing) ->
  assert.ok(typeOf(thing) in [
    'Object'
    'Undefined'
    'Null'
  ], "expected an Object, got #{JSON.stringify(thing)}")
  thing

parseKeyOpt = (opt) ->
  if (multi = opt.match(/^\[(.*)\]$/)) then multi[1].split(',') else opt

parseKeyOpts = (opts) ->
  opts.reduce(((xs, x) ->
    [k, v] = x.split('=')
    v ?= k
    merge(xs, hashMap(k, parseKeyOpt(v)))
  ), {})

mergeStrings = (toks, sep = '') ->
  reducer = (xs, x) ->
    y = xs.pop()
    xs.concat(if isString(x) and isString(y) then [[y,x].join(sep)] else [y,x])
  toks.reduce(reducer, []).filter((x) -> x? and x isnt '')

indexOfClosingCurly = (form) ->
  depth = 0
  for i in [0...form.length]
    switch form[i]
      when '{' then depth++
      when '}' then return i if not depth--
  return -1

interpolateSub = (form) ->
  ret = []
  while true
    if form.startsWith('${!}')
      ret.push(form[0...4])
      form = form[4..]
    else if form.startsWith('${')
      i = indexOfClosingCurly(form[2..])
      assert.notEqual(i, -1, "no closing curly: #{JSON.stringify(form)}")
      ret.push({Ref: form[2...i+2]})
      form = form[i+3..]
    else
      if (i = form.indexOf('${')) is -1
        ret.push(form)
        break
      else
        ret.push(form[0...i])
        form = form[i..]
  ret

#=============================================================================#
# AWS CLOUDFORMATION YAML TRANSFORMER BASE CLASS                              #
#=============================================================================#

class CfnTransformer extends YamlTransformer
  constructor: ({@basedir, @tempdir, @cache, @s3bucket, @s3prefix} = {}) ->
    super()

    if @s3bucket
      @s3uri = "https://s3.amazonaws.com/#{@s3bucket}/"
      @s3uri = "#{@s3uri}#{@s3prefix}" if @s3prefix

    @cache          ?= {}
    @basedir        ?= process.cwd()
    @tempdir        = path.resolve(@tempdir ? fs.mkdtempSync("#{os.tmpdir()}/"))
    @template       = null
    @resourceMacros = []
    @bindstack      = []

    #=========================================================================#
    # Define built-in CloudFormation macros (pass through verbatim).          #
    #=========================================================================#

    [
      'Base64'
      'FindInMap'
      'GetAZs'
      'ImportValue'
      'Select'
      'Split'
      'Cidr'
      'GetArtifactAtt'
      'GetParam'
      'And'
      'Equals'
      'If'
      'Not'
      'Or'
    ].forEach (x) => @defmacro(x)

    #=========================================================================#
    # Redefine and extend built-in CloudFormation macros.                     #
    #=========================================================================#

    @defmacro 'GetAtt', (form) =>
      'Fn::GetAtt': if isString(form) then split(form, '.', 2) else form

    @defmacro 'Join', (form) =>
      [sep, toks] = form
      switch (xs = mergeStrings(toks, sep)).length
        when 0 then ''
        when 1 then xs[0]
        else {'Fn::Join': [sep, xs]}

    @defmacro 'Ref', 'Ref', (form) =>
      if typeOf(form) is 'String'
        [ref, ks...] = form.split('.')
        switch
          when form.startsWith('$')     then {'Fn::Env': form[1..]}
          when form.startsWith('%')     then {'Fn::Get': form[1..]}
          when form.startsWith('@')     then {'Fn::Attr': form[1..]}
          when peek(@bindstack)[ref]?   then getIn(peek(@bindstack)[ref], ks)
          else {'Ref': form}
      else form

    @defmacro 'Sub', (form) =>
      switch typeOf(form)
        when 'String' then {'Fn::Join': ['', interpolateSub(form)]}
        else {'Fn::Sub': form}

    #=========================================================================#
    # Define special forms.                                                   #
    #=========================================================================#

    @defspecial 'Let', (form) =>
      if isArray(form)
        @withBindings(@walk(form[0]), => @walk(form[1]))
      else
        merge(peek(@bindstack), assertObject(@walk(form)))
        null

    #=========================================================================#
    # Define custom macros.                                                   #
    #=========================================================================#

    @defmacro 'Require', (form) =>
      form = [form] unless isArray(form)
      require(path.resolve(v))(@) for v in form
      null

    @defmacro 'Parameters', (form) =>
      Parameters: form.reduce(((xs, param) =>
        [name, opts...] = param.split(/ +/)
        opts = merge({Type: 'String'}, parseKeyOpts(opts))
        merge(xs, hashMap(name, opts))
      ), {})

    @defmacro 'Return', (form) =>
      Outputs: Object.keys(form).reduce(
        (xs, k) => merge(xs, hashMap(k, {Value: form[k]}))
        {}
      )

    @defmacro 'Resources', (form) =>
      ret = {}
      for logicalName, resource of form
        [logicalName, Type, opts...] = logicalName.split(/ +/)
        ret[logicalName] = if not Type
          if (m = @resourceMacros[resource.Type]) then m(resource) else resource
        else
          resource = merge({Type}, parseKeyOpts(opts), {Properties: resource})
          if (m = @resourceMacros[Type]) then m(resource) else resource
      Resources: ret

    @defmacro 'Attr', (form) =>
      {'Fn::GetAtt': split(form, '.', 2).map((x) => {'Fn::Sub': x})}

    @defmacro 'Get', (form) =>
      form = form.split('.') if isString(form)
      {'Fn::FindInMap': form.map((x) => {'Fn::Sub': x})}

    @defmacro 'Env', (form) =>
      ret = process.env[form]
      assert.ok(ret?, "required environment variable not set: #{form}")
      ret

    @defmacro 'Var', (form) =>
      {'Fn::ImportValue': {'Fn::Sub': form}}

    @defmacro 'Package', (form) =>
      form = {Path: form} if isString(form)
      {Path, Build, Parse} = form
      execShell(Build) if Build
      (
        if isDirectory(Path)
          @writeDir(Path)
        else if Parse
          @writeTemplate(Path)
        else
          @writeFile(Path)
      ).code

    @defmacro 'PackageURL', (form) =>
      @walk
        'Fn::Let': [
          {'Fn::Package': form}
          {'Fn::Sub': 'https://s3.amazonaws.com/${S3Bucket}/${S3Key}'}
        ]

    @defmacro 'PackageURI', (form) =>
      @walk
        'Fn::Let': [
          {'Fn::Package': form}
          {'Fn::Sub': 's3://${S3Bucket}/${S3Key}'}
        ]

    @defmacro 'PackageTemplateURL', (form) =>
      form = {Path: form} if isString(form)
      @walk {'Fn::PackageURL': Object.assign({Parse: true}, form)}

    @defmacro 'Yaml', (form) =>
      if isString(form) then yaml.safeLoad(form) else yaml.safeDump(form)

    @defmacro 'Json', (form) =>
      if isString(form) then JSON.parse(form) else JSON.stringify(form)

    @defmacro 'File', (form) =>
      fs.readFileSync(form)

    @defmacro 'TemplateFile', (form) =>
      form = @walk(@macros['Fn::Sub'](form))
      yaml.safeLoad(@transformTemplateFile(form))

    @defmacro 'Merge', (form) =>
      merge.apply(null, form)

    @defmacro 'DeepMerge', (form) =>
      deepMerge.apply(null, form)

    @defmacro 'Tags', (form) =>
      {Key: k, Value: form[k]} for k in Object.keys(form)

    @defresource 'Stack', (form) =>
      Type        = 'AWS::CloudFormation::Stack'
      Parameters  = {}
      Properties  = {Parameters}
      stackProps  = Object.keys(ResourceTypes[Type].Properties)
      for k, v of (form.Properties or {})
        (if k in stackProps then Properties else Parameters)[k] = v
      merge(form, {Type, Properties})

  abort: (msg...) ->
    ks = ['$'].concat(@keystack.map((x) -> "[#{x}]"))
    msg.unshift("at #{ks.join('')}:")
    msg.unshift("\n  in #{@template}:") if @template
    throw new Error(msg.join(' '))

  withBindings: (bindings, f) ->
    @bindstack.push(merge({}, peek(@bindstack), assertObject(bindings)))
    ret = f()
    @bindstack.pop()
    ret

  writePaths: (fileName, ext = '') ->
    fileName = "#{fileName}#{ext}"
    tmpPath:  @tmpPath(fileName),
    s3uri:    @s3path(fileName),
    code:     { S3Bucket: @s3bucket, S3Key: "#{@s3prefix}#{fileName}" }

  writeText: (text, ext) ->
    ret = @writePaths(md5(text), ext)
    fs.writeFileSync(ret.tmpPath, text)
    ret

  transformTemplateFile: (file) ->
    xformer = new @.constructor({@basedir, @tempdir, @cache, @s3bucket, @s3prefix})
    xformer.transformFile(file)

  writeTemplate: (file) ->
    @writeText(@transformTemplateFile(file), fileExt(file))

  writeFile: (file) ->
    ret = @writePaths(md5File(file), fileExt(file))
    fs.copyFileSync(file, ret.tmpPath)
    ret

  writeDir: (dir) ->
    tmpZip = @tmpPath("#{gensym()}.zip")
    execShell("zip -r #{tmpZip} .", {cwd: dir})
    ret = @writePaths(md5File(tmpZip), '.zip')
    fs.renameSync(tmpZip, ret.tmpPath)
    ret

  userPath: (file) ->
    path.relative(@basedir, file)

  tmpPath: (name) ->
    path.join(@tempdir, name)

  s3path: (name) ->
    if @s3uri then "#{@s3uri}#{name}" else @tmpPath(name)

  pushFile: (file, f) ->
    tpl = @template
    dir = process.cwd()
    @template = @userPath(file)
    process.chdir(path.dirname(file))
    ret = f(path.basename(file))
    process.chdir(dir)
    @template = tpl
    ret

  pushFileCaching: (file, f) ->
    key = @userPath(file)
    @cache[key] = @pushFile(file, f) unless @cache[key]
    @cache[key]

  defresource: (type, emit) ->
    @resourceMacros[type] = emit
    @

  transform: (text) ->
    @bindstack  = [{}]
    super(text)

  transformFile: (templateFile, doc) ->
    @pushFileCaching templateFile, (file) =>
      @transform(doc or fs.readFileSync(file).toString('utf-8'))

module.exports = CfnTransformer
