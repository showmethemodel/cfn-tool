# Template Preprocessor Macros

A few tasteful macros are provided that can be used to simplify YAML
CloudFormation templates by performing simple syntax transformations. **They
are completely optional** &mdash; there is no need to use them if you don't
like them :)

There are three kinds of macros supported by the preprocessor:

* **Top level macros** &mdash; custom-defined top-level sections of the
  CloudFormation template.
* **Resource macros** &mdash; custom resource types to simplify defining
  certain common resource types.
* **Custom YAML tags** &mdash; custom YAML tags that emit common syntactic patterns.

Additionally, a **resource DSL** is provided to simplify the resource structure
for all resources.

## Resource DSL

The basic [CloudFormation resource structure][1] has the following form:

```yaml
Resources:
  <LogicalID>:
    Type: <ResourceType>
    Properties:
      <PropertyKey>: <PropertyValue>
```

The resource DSL has the following form:

```yaml
Resources:
  <LogicalID> <ResourceType>:
    <PropertyKey>: <PropertyValue>
```

The resource structure also includes top-level fields (eg. `Condition`,
`DependsOn`, etc.) which may be included as perperties or as `<Field>=<Value>`
pairs.

```yaml
# INPUT
Resources:
  MyService AWS::AutoScaling::AutoScalingGroup Condition=CreateMyService DependsOn=[Bar,Baz]:
    AutoScalingGroupName: !Sub 'delivery-${Zone}-MyService'
    LaunchConfigurationName: !Ref MyServiceLaunchConfig
    UpdatePolicy: { AutoScalingScheduledAction: { IgnoreUnmodifiedGroupSizeProperties: true } }
```
```yaml
# OUTPUT
Resources:
  MyService:
    Type: 'AWS::AutoScaling::AutoScalingGroup'
    Condition: CreateMyService
    DependsOn: [ Bar, Baz ]
    Properties:
      AutoScalingGroupName: !Sub 'delivery-${Zone}-MyService'
      LaunchConfigurationName: !Ref MyServiceLaunchConfig
    UpdatePolicy: { AutoScalingScheduledAction: { IgnoreUnmodifiedGroupSizeProperties: true } }
```

Notice how `Condition`, `DependsOn`, and `UpdatePolicy` were all emitted as top
level fields of the resource structure, while `AutoScalingGroupName` and
`LaunchConfigurationName` were inserted as `Properties`. These top level field
names will never conflict with any resource property names so they are always
hoisted to the top level.

## Top Level Macros

Top level macros are defined with `deftoplevel` in [main.cljs][6].

### `Core::Bindings`

This section binds arbitrary YAML expressions to names local to this template.
The names are referenced by the built-in `!Ref` tag &mdash; the reference is
replaced by the bound expression. This works in all constructs supporting
`!Ref`, eg. in `!Sub` interpolated variables, etc.

```yaml
# INPUT
Core::Bindings:
  Foo: !If [ SomeCondition, default, !Ref FooParam ] # bind an expression to Foo

Resources:
  MyBucket AWS::S3::Bucket:
    BucketName: !Ref Foo # emit the expression bound to Foo
```
```yaml
# OUTPUT
Resources:
  MyBucket:
    Type: 'AWS::S3::Bucket'
    Properties:
      BucketName: !If [ SomeCondition, default, !Ref FooParam ]
```

### `Core::Parameters`

This section is handy for reducing boilerplate in the `Parameters` section of
a CloudFormation template. The value associated with this key is an array of
parameter names and options, with sensible defaults.

```yaml
# INPUT
Core::Parameters:
  - Zone
  - Subnets Type=CommaDelimitedList
  - Enabled Default=true AllowedValues=[true,false]
```
```yaml
# OUTPUT
Parameters:
  Zone:     { Type: String }
  Subnets:  { Type: CommaDelimitedList }
  Enabled:  { Type: String, Default: 'true', AllowedValues: [ 'true', 'false' ] }
```

## Resource Macros

Resource macros are defined with `defresource` in [main.cljs][6].

### `Core::Stack`

Simplifies the [`AWS::CloudFormation::Stack`][5] structure.

```yaml
# INPUT
Resources:
  Foo Core::Stack:
    TemplateURL: ../core/lib/foo.yml
    TimeoutInMinutes: 2
    Param1: val1
    Param2: val2
```
```yaml
# OUTPUT
Resources:
  Foo:
    Type: 'AWS::CloudFormation::Stack'
    Properties:
      TemplateURL: ../core/lib/foo.yml
      TimeoutInMinutes: 2
      Parameters:
        Param1: val1
        Param2: val2
```

Notice that top level properties (eg. `TemplateURL`, `TimeoutInMinutes`, etc.)
are hoisted, and other fields (eg. `Param1` and `Param2`) are assigned as
parameters of the template. Obviously, don't make templates with parameters
whose names conflict with properties of the stack resource structure.

## Custom YAML Tags

Custom YAML tags are defined with `deftag` in [main.cljs][6]. Custom tags can
be used as "short tags" or "full maps":

```yaml
# short tag
Foo: !Var bar
```
```yaml
# full map
Foo: { 'Core::Var': bar }
```

> **Note:** Short tags cannot be nested in YAML (the parser will reject it) so
> in some cases it may be necessary to fall back to the full map representation.

### `Core::Attr` &mdash; `!Attr`

Expands to a [`Fn::GetAtt`][8] expression with [`Fn::Sub`][4] interpolation on
the dot path segments.

```yaml
# INPUT
Foo: !Attr 'Thing.${Bar}'
```
```yaml
# OUTPUT
Foo:
  'Fn::GetAtt': [ Thing, { Ref: Bar } ]
```

### `Core::Env` &mdash; `!Env`

Expands to the value of an environment variable in the environment of the
preprocessor process. An exception is thrown if the variable is unset.

```yaml
# INPUT
Foo: !Env USER
```
```yaml
# OUTPUT
Foo: micha
```

### `Core::Get` &mdash; `!Get`

Expands to an expression using [`Fn::FindInMap`][11] to look up a value from a
[template mapping structure][12]. References are interpolated in the argument
and dots are used to separate segments of the path (similar to [`Fn::GetAtt`][8]).

```yaml
# INPUT
Foo: !Get 'Config.${AWS::Region}.ImageId'
```
```yaml
# OUTPUT
Foo:
  'Fn::FindInMap':
    - Config
    - Ref: 'AWS::Region'
    - ImageId
```

### `Core::Include` &mdash; N/A

Expands to a [`Fn::Transform`][9] [`AWS::Include`][10] CloudFormation macro.
References are interpolated in its argument. There is no short tag because the
result will be merged into the parent map, so it must be represented
syntactically as key and value.

```yaml
# INPUT
Mappings:
  Core::Include: '../config/${$ZONE}.yml'
```
```yaml
Mappings:
  'Fn::Transform':
    Name: 'AWS::Include'
    Parameters:
      Location: ../config/test.yml
```

### `Ref` &mdash; `!Ref`

The builtin [`Ref`][7] intrinsic function has been extended to support
references to environment variables, mappings, resource attributes, and bound
names in addition to its normal functionality.

* **Environment variable references** start with `$` (see [`!Env`](#coreenv--env) above).
* **Mapping attribute references** start with `%` (see [`!Get`](#coreget--get) above).
* **Resource attribute references** start with `@` (see [`!Attr`](#coreattr--attr) above).
* **Bound names** are referenced with no prefix (see [`Core::Bindings`](#corebindings) above).

```yaml
# INPUT
Foo: !Ref Zone
Bar: !Ref '$USER'
Baz: !Ref '%Config.${AWS::Region}.MainVpcSubnet'
Baf: !Ref '@Thing.Outputs.StreamName'
```
```yaml
# OUTPUT
Foo: { Ref: Zone }
Bar: micha
Baz: { 'Fn::FindInMap': [ Config, { Ref: 'AWS::Region' }, MainVpcSubnet ] }
Baf: { 'Fn::GetAtt': [ Thing, Outputs.StreamName ] }
```

> **Note:** The `Ref` function is used by all other functions that support
> interpolation of references in strings, (eg. [`Fn::Sub`][4], [`Core::Var`](#corevar--var),
> etc.) so these functions also support environment variable and resource
> attribute references.

### `Core::Tags` &mdash; `!Tags`

Expands a map to a list of [resource tag structures][2].

```yaml
# INPUT
Resources:
  Foo AWS::S3::Bucket:
    BucketName: foo-bucket
    Tags: !Tags
      ThreatLevel: infinity
      Maximumness: enforced
```
```yaml
# OUTPUT
Resources:
  Foo:
    Type: 'AWS::S3::Bucket'
    Properties:
      BucketName: foo-bucket
      Tags:
        - { Key: ThreatLevel, Value: infinity }
        - { Key: Maximumness, Value: enforced }
```

### `Core::Var` &mdash; `!Var`

Expands to a [`Fn::ImportValue`][3] call with a nested [`Fn::Sub`][4] to
perform variable interpolation on the export name.

```yaml
# INPUT
Resources:
  Foo:
    Type: AWS::S3::Bucket
    Properties:
      BucketName: !Var 'delivery-${Zone}-Foop'
```
```yaml
# OUTPUT
Resources:
  Foo:
    Type: 'AWS::S3::Bucket'
    Properties:
      BucketName: { 'Fn::ImportValue': !Sub 'delivery-${Zone}-Foop' }
```

[1]: https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/resources-section-structure.html
[2]: https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/aws-properties-resource-tags.html
[3]: https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/intrinsic-function-reference-importvalue.html
[4]: https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/intrinsic-function-reference-sub.html
[5]: https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/aws-properties-stack.html
[6]: ../src/template-preprocess/src/tpp/main.cljs
[7]: https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/intrinsic-function-reference-ref.html
[8]: https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/intrinsic-function-reference-getatt.html
[9]: https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/intrinsic-function-reference-transform.html
[10]: https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/create-reusable-transform-function-snippets-and-add-to-your-template-with-aws-include-transform.html 
[11]: https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/intrinsic-function-reference-findinmap.html
[12]: https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/mappings-section-structure.html
