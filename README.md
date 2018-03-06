# boilerplate

libboilerplate generates boilerplate code handling common tasks. Code generation is driven by user-defined attributes.
Use `mixin(GenerateAll);` to handle all attributes. This is usually the right thing to do.
By default, boilerplate covers all non-static member fields of the class, although accessors can also be
explicitly applied to static fields.

Boilerplate will generate accessors, toString functions, invariants and constructors.

libboilerplate is a superset of libaccessors.

## boilerplate.accessors

- **@Read:** Generate an accessor that returns the field. Will `dup` arrays when needed. Unneeded const is discarded.
- **@ConstRead:** Generate an accessor that returns the field as const.
- **@RefRead:** Generate an accessor that returns the field as `ref`. *Deprecated.*
- **@Write:** Generate an accessor that sets the field to a value. Will `dup` arrays when needed.

A string can be passed to the attribute to determine the visibility of the accessor, such as
`@ConstRead("protected")` or `@Write("private")`.

## boilerplate.autostring

Autostring implements Funkwerk standard toString logic.
Both sink-based and string-based toString functions are generated.

The string takes the form "ClassName(field = value, field = value, field = value)".

If the type is a class, and the superclass has a toString method, it is output first.

If toString is already defined, it is called instead.

By default, fields that have the same name as their type are not labelled.
For array types, this requires pluralized names. (`Class[] classes` is not labeled.)

The following attributes can be applied to the whole structure:

- **@(ToString.Naked):** Do not include "ClassName()".
- **@(ToString.ExcludeSuper):** Do not include the parent class.

The following attributes can be applied to fields:

- **@(ToString.Exclude):** Exclude a field from toString.
- **@(ToString.Include):** Explicitly include a field. Useful for printing manual getter functions.
- **@(ToString.Optional):** Include the field if it's non-empty, non-null or non-zero. Nullable types are always optional.
- **@(ToString.Unlabeled):** Skip the label; "ClassName(value)".
- **@(ToString.Labeled):** Explicitly include the label.
- **@ToStringHandler!pred:** `pred(a)`: use \lstinline{pred} to transform the field into a string.
- **@ToStringHandler!pred:** `pred(a, ref SinkWriter)`: use \lstinline{pred} to feed the field into a SinkWriter.

**Note** that ToStringHandlers are generally a code smell, since they imply a field whose format does not
depend on just the type. ToStringHandler is intended for quick and dirty toString conversions, to be cleaned up at the
earliest convenience.

## boilerplate.conditions

These attributes will generate invariant checks, ensuring that the value of the field does not
violate the condition. Note that `@RefRead` fields *cannot* be reliably verified!

When a field is `Nullable`, the check is applied to its value, if one is present.

- **@NonEmpty:** `!field.empty()`
- **@NonNull:** `field !is null`
- **@NonInit:** `field !is T.init`
- **@AllNonNull:** `field !is null` for all fields of an array

When using the `@Write` accessor, the defined conditions will be checked separately on assignment.
When a check fails, the value of the field will be unchanged.

## boilerplate.constructor

A constructor is generated that takes one parameter for every field in the class. The parameters are in the same order
as the fields. The constructor is `public` by default.

Mark a field with `@Default!value` to provide a default value
for the field's parameter in the constructor call. If the value is only valid at runtime, use
`@Default!(() => value)`.

As with accessors, arrays passed to the constructor are `dup`ed, even when wrapped in Nullable.

If the superclass also has a *boilerplate-generated* constructor, the fields of that constructor are
also included. In that case, depending on what fields have default values (implicit) or not (explicit),
the order of arguments is "parent's explicit, child's explicit, child's implicit, parent's implicit."

A field can be tagged with `@(This.Exclude)` to exclude it from the generated constructor.

The following attributes can be applied to the whole structure:

- **@(This.Private):** Mark the constructor as `private`.
- **@(This.Protected):** Mark the constructor as `protected`.
- **@(This.Package):** Mark the constructor as `package`.
