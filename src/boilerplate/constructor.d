module boilerplate.constructor;

import std.algorithm : canFind, map;
import std.meta : AliasSeq, allSatisfy, ApplyLeft;
import std.range : array;
import std.traits : hasElaborateDestructor, isInstanceOf, isNested;
import std.typecons : Tuple;

version(unittest)
{
    import unit_threaded.should;
}

/++
GenerateThis is a mixin string that automatically generates a this() function, customizable with UDA.
+/
public enum string GenerateThis = `
    import boilerplate.constructor :
        ConstructorField, GenerateThisTemplate, getUDADefaultOrNothing, saveConstructorInfo;
    import std.string : replace;
    mixin GenerateThisTemplate;
    mixin(typeof(this).generateThisImpl());
`;

/**
 * `GenerateThis` creates a constructor with a parameter for every field.
 */
@("creates a constructor")
unittest
{
    class Class
    {
        int field;

        mixin(GenerateThis);
    }

    auto obj = new Class(5);

    obj.field.shouldEqual(5);
}

/**
 * When the super class also has a generated constructor, it will be called first.
 */
@("calls the super constructor if it exists")
unittest
{
    class Class
    {
        int field;

        mixin(GenerateThis);
    }

    class Child : Class
    {
        int field2;

        mixin(GenerateThis);
    }

    auto obj = new Child(5, 8);

    obj.field.shouldEqual(5);
    obj.field2.shouldEqual(8);
}

/**
 * Methods are ignored when generating constructors.
 */
@("separates fields from methods")
unittest
{
    class Class
    {
        int field;

        void method() { }

        mixin(GenerateThis);
    }

    auto obj = new Class(5);

    obj.field.shouldEqual(5);
}

/**
 * When passing arrays to the constructor, these arrays are automatically `dup`-ed.
 */
@("dups arrays")
unittest
{
    class Class
    {
        int[] array;

        mixin(GenerateThis);
    }

    auto array = [2, 3, 4];
    auto obj = new Class(array);

    array[0] = 1;
    obj.array[0].shouldEqual(2);
}

/**
 * Arrays passed to the constructor are `dup`-ed even if they're inside a Nullable.
 */
@("dups arrays hidden behind Nullable")
unittest
{
    import std.typecons : Nullable, nullable;

    class Class
    {
        Nullable!(int[]) array;

        mixin(GenerateThis);
    }

    auto array = [2, 3, 4];
    auto obj = new Class(array.nullable);

    array[0] = 1;
    obj.array.get[0].shouldEqual(2);

    obj = new Class(Nullable!(int[]).init);
    obj.array.isNull.shouldBeTrue;
}

/**
 * Associative arrays are also `dup`-ed.
 */
@("dups associative arrays")
unittest
{
    class Class
    {
        int[int] array;

        mixin(GenerateThis);
    }

    auto array = [2: 3];
    auto obj = new Class(array);

    array[2] = 4;
    obj.array.shouldEqual([2: 3]);
}

/**
 * `@(This.Default!value)` defines a default value for the constructor parameter.
 */
@("uses default value for default constructor parameter")
unittest
{
    class Class
    {
        @(This.Default!5)
        int value = 5;

        mixin(GenerateThis);
    }

    auto obj1 = new Class();

    obj1.value.shouldEqual(5);

    auto obj2 = new Class(6);

    obj2.value.shouldEqual(6);
}

/**
 * When using `GenerateThis` in an empty struct, no constructor is created.
 *
 * This is because D does not allow empty constructor methods.
 */
@("creates no constructor for an empty struct")
unittest
{
    struct Struct
    {
        mixin(GenerateThis);
    }

    auto strct = Struct();
}

/**
 * `@(This.Default!(lambda))` calls the lambda to generate the default value.
 *
 * This is to handle cases like `@(This.Default!(new Class))`, where D would allocate
 * the class during startup and reuse the same reference for every constructor call.
 */
@("properly generates new default values on each call")
unittest
{
    import std.conv : to;

    class Class
    {
        @(This.Default!(() => new Object))
        Object obj;

        mixin(GenerateThis);
    }

    auto obj1 = new Class();
    auto obj2 = new Class();

    (cast(void*) obj1.obj).shouldNotEqual(cast(void*) obj2.obj);
}

/**
 * When the superclass has a generated constructor, the order of parameters is:
 *
 * - Super class fields
 * - Class fields
 * - Class fields with default value
 * - Super class fields with default value
 */
@("establishes the parent-child parameter order: parent explicit, child explicit, child implicit, parent implicit.")
unittest
{
    class Parent
    {
        int field1;

        @(This.Default!2)
        int field2 = 2;

        mixin(GenerateThis);
    }

    class Child : Parent
    {
        int field3;

        @(This.Default!4)
        int field4 = 4;

        mixin(GenerateThis);
    }

    auto obj = new Child(1, 2, 3, 4);

    obj.field1.shouldEqual(1);
    obj.field3.shouldEqual(2);
    obj.field4.shouldEqual(3);
    obj.field2.shouldEqual(4);
}

/**
 * No constructor parameter is generated for static fields.
 */
@("disregards static fields")
unittest
{
    class Class
    {
        static int field1;
        int field2;

        mixin(GenerateThis);
    }

    auto obj = new Class(5);

    obj.field1.shouldEqual(0);
    obj.field2.shouldEqual(5);
}

/**
 * Immutable arrays are supported as constructor parameters.
 */
@("can initialize with immutable arrays")
unittest
{
    class Class
    {
        immutable(Object)[] array;

        mixin(GenerateThis);
    }
}

/**
 * `@(This.Private/Protected/Public)` can be used to define the visibility scope of the constructor.
 */
@("can define scope for constructor")
unittest
{
    @(This.Private)
    class PrivateClass
    {
        mixin(GenerateThis);
    }

    @(This.Protected)
    class ProtectedClass
    {
        mixin(GenerateThis);
    }

    @(This.Package)
    class PackageClass
    {
        mixin(GenerateThis);
    }

    @(This.Package("boilerplate"))
    class SubPackageClass
    {
        mixin(GenerateThis);
    }

    class PublicClass
    {
        mixin(GenerateThis);
    }

    static assert(__traits(getProtection, PrivateClass.__ctor) == "private");
    static assert(__traits(getProtection, ProtectedClass.__ctor) == "protected");
    static assert(__traits(getProtection, PackageClass.__ctor) == "package");
    // getProtection does not return the package name of a package() attribute
    // static assert(__traits(getProtection, SubPackageClass.__ctor) == `package(boilerplate)`);
    static assert(__traits(getProtection, PublicClass.__ctor) == "public");
}

/**
 * `@(This.Private/Protected/Public)` also assigns a visibility scope to the generated builder.
 */
@("will assign the same scope to Builder")
unittest
{
    @(This.Private)
    class PrivateClass
    {
        mixin(GenerateThis);
    }

    @(This.Protected)
    class ProtectedClass
    {
        mixin(GenerateThis);
    }

    @(This.Package)
    class PackageClass
    {
        mixin(GenerateThis);
    }

    @(This.Package("boilerplate"))
    class SubPackageClass
    {
        mixin(GenerateThis);
    }

    class PublicClass
    {
        mixin(GenerateThis);
    }

    static assert(__traits(getProtection, PrivateClass.Builder) == "private");
    static assert(__traits(getProtection, ProtectedClass.Builder) == "protected");
    static assert(__traits(getProtection, PackageClass.Builder) == "package");
    static assert(__traits(getProtection, PublicClass.Builder) == "public");
}

/**
 * `@(This.Default)` without a parameter uses the default value of the type.
 */
@("empty default tag means T()")
unittest
{
    class Class
    {
        @(This.Default)
        string s;

        @(This.Default)
        int i;

        mixin(GenerateThis);
    }

    (new Class()).i.shouldEqual(0);
    (new Class()).s.shouldEqual(string.init);
}

/**
 * `@(This.Exclude)` excludes a field from being set by the generated constructor.
 */
@("can exclude fields from constructor")
unittest
{
    class Class
    {
        @(This.Exclude)
        int i = 5;

        mixin(GenerateThis);
    }

    (new Class).i.shouldEqual(5);
}

/**
 * Even if the class holds a field that is not const, a const array can be passed to it
 * as long as the `dup` of this field does not leak mutable references.
 */
@("marks duppy parameters as const when this does not prevent dupping")
unittest
{

    struct Struct
    {
    }

    class Class
    {
        Struct[] values_;

        mixin(GenerateThis);
    }

    const Struct[] constValues;
    auto obj = new Class(constValues);
}

/**
 * Property functions are disregarded by the generated constructor
 */
@("does not include property functions in constructor list")
unittest
{
    class Class
    {
        int a;

        @property int foo() const
        {
            return 0;
        }

        mixin(GenerateThis);
    }

    static assert(__traits(compiles, new Class(0)));
    static assert(!__traits(compiles, new Class(0, 0)));
}

/**
 * When no parameters need to be dupped, the generated constructor is `@nogc`.
 */
@("declares @nogc on non-dupping constructors")
@nogc unittest
{
    struct Struct
    {
        int a;

        mixin(GenerateThis);
    }

    auto str = Struct(5);
}

/**
 * `@(This.Init!value)` defines a value for the field that will be assigned in the constructor,
 * and excludes the field from being a constructor parameter.
 */
@("can initialize fields using init value")
unittest
{
    class Class
    {
        @(This.Init!5)
        int field1;

        @(This.Init!(() => 8))
        int field2;

        mixin(GenerateThis);
    }

    auto obj = new Class;

    obj.field1.shouldEqual(5);
    obj.field2.shouldEqual(8);
}

/**
 * `@(This.Init!lambda)`, like `@(This.Default!lambda)`, will be called automatically with `this`
 * to determine the initializer value.
 */
@("can initialize fields using init value, with lambda that accesses previous value")
unittest
{
    class Class
    {
        int field1;

        @(This.Init!(self => self.field1 + 5))
        int field2;

        mixin(GenerateThis);
    }

    auto obj = new Class(5);

    obj.field1.shouldEqual(5);
    obj.field2.shouldEqual(10);
}

/**
 * `@(This.Init!lambda)` can allocate runtime values.
 */
@("can initialize fields with allocated types")
unittest
{
    class Class1
    {
        @(This.Init!(self => new Object))
        Object object;

        mixin(GenerateThis);
    }

    class Class2
    {
        @(This.Init!(() => new Object))
        Object object;

        mixin(GenerateThis);
    }

    class Class3 : Class2
    {
        mixin(GenerateThis);
    }
}

/**
 * `GenerateThis` creates a `.Builder()` property that can be used to incrementally construct the value.
 *
 * `builder.value` will call the generated constructor with the assigned values.
 */
@("generates Builder class that gathers constructor parameters, then calls constructor with them")
unittest
{
    static class Class
    {
        int field1;
        int field2;
        int field3;

        mixin(GenerateThis);
    }

    auto obj = {
        with (Class.Builder())
        {
            field1 = 1;
            field2 = 2;
            field3 = 3;
            return value;
        }
    }();

    with (obj)
    {
        field1.shouldEqual(1);
        field2.shouldEqual(2);
        field3.shouldEqual(3);
    }
}

/**
 * The order in which `Builder` fields are set is irrelevant.
 */
@("builder field order doesn't matter")
unittest
{
    static class Class
    {
        int field1;
        int field2;
        int field3;

        mixin(GenerateThis);
    }

    auto obj = {
        with (Class.Builder())
        {
            field3 = 1;
            field1 = 2;
            field2 = 3;
            return value;
        }
    }();

    with (obj)
    {
        field1.shouldEqual(2);
        field2.shouldEqual(3);
        field3.shouldEqual(1);
    }
}

/**
 * `Builder` fields with a `@(This.Default)` value can be omitted.
 */
@("default fields can be left out when assigning builder")
unittest
{
    static class Class
    {
        int field1;
        @(This.Default!5)
        int field2;
        int field3;

        mixin(GenerateThis);
    }

    // constructor is this(field1, field3, field2 = 5)
    auto obj = {
        with (Class.Builder())
        {
            field1 = 1;
            field3 = 3;
            return value;
        }
    }();

    with (obj)
    {
        field1.shouldEqual(1);
        field2.shouldEqual(5);
        field3.shouldEqual(3);
    }
}

/**
 * `Builder` can be used with structs as well as classes.
 */
@("supports Builder in structs")
unittest
{
    struct Struct
    {
        int field1;
        int field2;
        int field3;

        mixin(GenerateThis);
    }

    auto value = {
        with (Struct.Builder())
        {
            field1 = 1;
            field3 = 3;
            field2 = 5;
            return value;
        }
    }();

    static assert(is(typeof(value) == Struct));

    with (value)
    {
        field1.shouldEqual(1);
        field2.shouldEqual(5);
        field3.shouldEqual(3);
    }
}

/**
 * `Builder` fields don't contain the trailing newline of a private field.
 */
@("builder strips trailing underlines")
unittest
{
    struct Struct
    {
        private int a_;

        mixin(GenerateThis);
    }

    auto builder = Struct.Builder();

    builder.a = 1;

    auto value = builder.value;

    value.shouldEqual(Struct(1));
}

/**
 * When a field in the type has a generated constructor itself, its fields can be set directly
 * on a `Builder` of the outer type.
 */
@("builder supports nested initialization")
unittest
{
    struct Struct1
    {
        int a;
        int b;

        mixin(GenerateThis);
    }

    struct Struct2
    {
        int c;
        Struct1 struct1;
        int d;

        mixin(GenerateThis);
    }

    auto builder = Struct2.Builder();

    builder.struct1.a = 1;
    builder.struct1.b = 2;
    builder.c = 3;
    builder.d = 4;

    auto value = builder.value;

    static assert(is(typeof(value) == Struct2));

    with (value)
    {
        struct1.a.shouldEqual(1);
        struct1.b.shouldEqual(2);
        c.shouldEqual(3);
        d.shouldEqual(4);
    }
}

/**
 * `Builder` can use `@(This.Default)` values for nested fields.
 */
@("builder supports defaults for nested values")
unittest
{
    struct Struct1
    {
        int a;
        int b;

        mixin(GenerateThis);
    }

    struct Struct2
    {
        int c;
        @(This.Default!(Struct1(3, 4)))
        Struct1 struct1;
        int d;

        mixin(GenerateThis);
    }

    auto builder = Struct2.Builder();

    builder.c = 1;
    builder.d = 2;

    builder.value.shouldEqual(Struct2(1, 2, Struct1(3, 4)));
}

/**
 * `Builder` also allows assigning a single value directly for a nested `Builder` field.
 */
@("builder supports direct value assignment for nested values")
unittest
{
    struct Struct1
    {
        int a;
        int b;

        mixin(GenerateThis);
    }

    struct Struct2
    {
        int c;
        Struct1 struct1;
        int d;

        mixin(GenerateThis);
    }

    auto builder = Struct2.Builder();

    builder.struct1 = Struct1(2, 3);
    builder.c = 1;
    builder.d = 4;

    builder.value.shouldEqual(Struct2(1, Struct1(2, 3), 4));
}

/**
 * When a `Builder` field is an array, it can be initialized by
 * specifying the value for each desired index.
 */
@("builder supports recursive array index initialization")
unittest
{
    struct Struct1
    {
        int value;

        mixin(GenerateThis);
    }

    struct Struct2
    {
        Struct1[] array;

        mixin(GenerateThis);
    }

    auto builder = Struct2.Builder();

    builder.array[0].value = 1;
    builder.array[1].value = 2;

    builder.value.shouldEqual(Struct2([Struct1(1), Struct1(2)]));
}

/**
 * `Builder` handles fields that are aliased to `this`.
 */
@("builder supports nested struct with alias this")
unittest
{
    struct Struct2
    {
        string text;

        alias text this;

        mixin(GenerateThis);
    }

    struct Struct1
    {
        Struct2 nested;

        mixin(GenerateThis);
    }

    auto builder = Struct1.Builder();

    builder.nested.text = "foo";

    builder.value.shouldEqual(Struct1(Struct2("foo")));
}

/**
 * When a `Builder` field is an array, it can also be initialized by appending values.
 */
@("builder supports arrays as values")
unittest
{
    struct Struct1
    {
        int value;

        mixin(GenerateThis);
    }

    struct Struct2
    {
        Struct1[] array;

        mixin(GenerateThis);
    }

    auto builder = Struct2.Builder();

    builder.array ~= Struct1(1);
    builder.array ~= Struct1(2);

    builder.value.shouldEqual(Struct2([Struct1(1), Struct1(2)]));
}

/**
 * When a value has been assigned to a recursive `Builder` field, its fields can still
 * be individually overridden.
 * This uses the `BuilderFrom` reverse-`Builder` property.
 */
@("builder supports overriding value assignment with field assignment later")
unittest
{
    struct Struct1
    {
        int a;
        int b;

        mixin(GenerateThis);
    }

    struct Struct2
    {
        Struct1 struct1;

        mixin(GenerateThis);
    }

    auto builder = Struct2.Builder();

    builder.struct1 = Struct1(2, 3);
    builder.struct1.b = 4;

    builder.value.shouldEqual(Struct2(Struct1(2, 4)));
}

/**
 * `Builder` does not attempt to use `BuilderFrom` when this would leak a non-constant reference.
 */
@("builder doesn't try to use BuilderFrom for types where nonconst references would have to be taken")
unittest
{
    import core.exception : AssertError;

    struct Struct1
    {
        int a;

        private Object[] b_;

        mixin(GenerateThis);
    }

    struct Struct2
    {
        Struct1 struct1;

        mixin(GenerateThis);
    }

    // this should at least compile, despite the BuilderFrom hack not working with Struct1
    auto builder = Struct2.Builder();

    builder.struct1 = Struct1(2, null);

    void set()
    {
        builder.struct1.b = null;
    }

    set().shouldThrow!AssertError(
        "Builder: cannot set sub-field directly since field is already " ~
        "being initialized by value (and BuilderFrom is unavailable in Struct1)");
}

/**
 * When a recursive `Builder` field has already been directly assigned, it cannot be
 * later overwritten with a whole-value assignment.
 */
@("builder refuses overriding field assignment with value assignment")
unittest
{
    import core.exception : AssertError;

    struct Struct1
    {
        int a;
        int b;

        mixin(GenerateThis);
    }

    struct Struct2
    {
        Struct1 struct1;

        mixin(GenerateThis);
    }

    auto builder = Struct2.Builder();

    builder.struct1.b = 4;

    void set()
    {
        builder.struct1 = Struct1(2, 3);
    }
    set().shouldThrow!AssertError("Builder: cannot set field by value since a subfield has already been set.");
}

/**
 * `Builder` supports assigning const fields.
 */
@("builder supports const args")
unittest
{
    struct Struct
    {
        const int a;

        mixin(GenerateThis);
    }

    with (Struct.Builder())
    {
        a = 5;

        value.shouldEqual(Struct(5));
    }
}

/**
 * `Builder` supports assigning recursive values with a destructor.
 */
@("builder supports fields with destructor")
unittest
{
    static struct Struct1
    {
        ~this() pure @safe @nogc nothrow { }
    }

    struct Struct2
    {
        Struct1 struct1;

        mixin(GenerateThis);
    }

    with (Struct2.Builder())
    {
        struct1 = Struct1();

        value.shouldEqual(Struct2(Struct1()));
    }
}

/**
 * When a `Builder` field is `Nullable!T`, it can be directly assigned a `T`.
 */
@("builder supports direct assignment to Nullables")
unittest
{
    import std.typecons : Nullable, nullable;

    struct Struct
    {
        const Nullable!int a;

        mixin(GenerateThis);
    }

    with (Struct.Builder())
    {
        a = 5;

        value.shouldEqual(Struct(5.nullable));
    }
}

/**
 * When a `Builder` field is `Nullable!T`, and `T` has a `Builder`, `T`'s fields can be directly assigned.
 */
@("builder with passthrough assignment to Nullable structs")
unittest
{
    import std.typecons : Nullable, nullable;

    struct Struct1
    {
        int a;

        mixin(GenerateThis);
    }

    struct Struct2
    {
        @(This.Default)
        Nullable!Struct1 b;

        mixin(GenerateThis);
    }

    with (Struct2.Builder())
    {
        value.shouldEqual(Struct2(Nullable!Struct1()));

        b.a = 5;

        value.shouldEqual(Struct2(Nullable!Struct1(Struct1(5))));
    }
}

/**
 * When a `Builder` field is `Nullable!T`, and `T` has a `Builder`, `T` can still be assigned either as
 * `T` or `Nullable!T`.
 */
@("builder with value assignment to Nullable struct field")
unittest
{
    import std.typecons : Nullable, nullable;

    struct Struct1
    {
        mixin(GenerateThis);
    }

    struct Struct2
    {
        @(This.Default)
        Nullable!Struct1 value;

        mixin(GenerateThis);
    }

    with (Struct2.Builder())
    {
        builderValue.shouldEqual(Struct2());

        value = Struct1();

        builderValue.shouldEqual(Struct2(Struct1().nullable));
    }

    with (Struct2.Builder())
    {
        value = Nullable!Struct1();

        builderValue.shouldEqual(Struct2());
    }
}

/**
 * A value with `GenerateThis` can be turned back into a builder using `BuilderFrom()`.
 * This can be used to reassign immutable fields.
 */
@("builder supports reconstruction from value")
unittest
{
    import std.typecons : Nullable, nullable;

    struct Struct
    {
        private int a_;

        int[] b;

        mixin(GenerateThis);
    }

    const originalValue = Struct(2, [3]);

    with (originalValue.BuilderFrom())
    {
        a = 5;

        value.shouldEqual(Struct(5, [3]));
    }
}

/**
 * When a type already has a `value` field, `builderValue` can be used to get the builder value.
 */
@("builder supports struct that already contains a value field")
unittest
{
    import std.typecons : Nullable, nullable;

    struct Struct
    {
        private int value_;

        mixin(GenerateThis);
    }

    with (Struct.Builder())
    {
        value = 5;

        builderValue.shouldEqual(Struct(5));
    }
}

/**
 * `Builder` will handle structs that contain structs with `@disable(this)`.
 */
@("builder supports struct that contains struct that has @disable(this)")
unittest
{
    import std.typecons : Nullable, nullable;

    static struct Inner
    {
        private int i_;

        @disable this();

        mixin(GenerateThis);
    }

    static struct Struct
    {
        private Inner inner_;

        mixin(GenerateThis);
    }

    with (Struct.Builder())
    {
        inner.i = 3;

        value.shouldEqual(Struct(Inner(3)));
    }
}

@("destructors with code that is unsafe, system or throws exceptions")
{
    struct S
    {
        ~this() { throw new Exception("test"); }
    }

    struct T
    {
        S s;

        mixin(GenerateThis);
    }
}

@("builder supports appending to transitive non-const fields")
unittest
{
    struct Struct1
    {
        int[] values;

        mixin(GenerateThis);
    }

    struct Struct2
    {
        Struct1[] array;

        mixin(GenerateThis);
    }

    auto builder = Struct2.Builder();

    builder.array ~= [Struct1([1]), Struct1([2])];

    builder.value.shouldEqual(Struct2([Struct1([1]), Struct1([2])]));
}

import std.string : format;

enum GetSuperTypeAsString_(string member) = format!`typeof(super).ConstructorInfo.FieldInfo.%s.Type`(member);

enum GetMemberTypeAsString_(string member) = format!`typeof(this.%s)`(member);

enum SuperDefault_(string member) = format!`typeof(super).ConstructorInfo.FieldInfo.%s.fieldDefault`(member);

enum MemberDefault_(string member) =
    format!`getUDADefaultOrNothing!(typeof(this.%s), __traits(getAttributes, this.%s))`(member, member);

enum SuperUseDefault_(string member)
    = format!(`typeof(super).ConstructorInfo.FieldInfo.%s.useDefault`)(member);

enum MemberUseDefault_(string member)
    = format!(`udaIndex!(This.Default, __traits(getAttributes, this.%s)) != -1`)(member);

enum SuperAttributes_(string member)
    = format!(`typeof(super).ConstructorInfo.FieldInfo.%s.attributes`)(member);

enum MemberAttributes_(string member)
    = format!(`__traits(getAttributes, this.%s)`)(member);

mixin template GenerateThisTemplate()
{
    private static generateThisImpl()
    {
        if (!__ctfe)
        {
            return null;
        }

        import boilerplate.constructor :
            filterCanFind, GetMemberTypeAsString_, GetSuperTypeAsString_,
            mapFormat, MemberAttributes_, MemberDefault_, MemberUseDefault_,
            SuperAttributes_, SuperDefault_, SuperUseDefault_,
            This;
        import boilerplate.util :
            bucketSort, GenNormalMemberTuple, needToDup,
            optionallyRemoveTrailingUnderline,
            removeTrailingUnderline, reorder, udaIndex;
        import std.algorithm : all, canFind, filter, map;
        import std.meta : Alias, aliasSeqOf, staticMap;
        import std.range : array, drop, empty, iota, zip;
        import std.string : endsWith, format, join;
        import std.typecons : Nullable;

        mixin GenNormalMemberTuple;

        string result = null;

        string visibility = "public";

        foreach (uda; __traits(getAttributes, typeof(this)))
        {
            static if (is(typeof(uda) == ThisEnum))
            {
                static if (uda == This.Protected)
                {
                    visibility = "protected";
                }
                static if (uda == This.Private)
                {
                    visibility = "private";
                }
            }
            else static if (is(uda == This.Package))
            {
                visibility = "package";
            }
            else static if (is(typeof(uda) == This.Package))
            {
                visibility = "package(" ~ uda.packageMask ~ ")";
            }
        }

        string[] constructorAttributes = ["pure", "nothrow", "@safe", "@nogc"];

        static if (is(typeof(typeof(super).ConstructorInfo)))
        {
            enum argsPassedToSuper = typeof(super).ConstructorInfo.fields.length;
            enum members = typeof(super).ConstructorInfo.fields ~ [NormalMemberTuple];
            enum string[] CombinedArray(alias SuperPred, alias MemberPred) = ([
                staticMap!(SuperPred, aliasSeqOf!(typeof(super).ConstructorInfo.fields)),
                staticMap!(MemberPred, NormalMemberTuple)
            ]);
            constructorAttributes = typeof(super).GeneratedConstructorAttributes_;
        }
        else
        {
            enum argsPassedToSuper = 0;
            static if (NormalMemberTuple.length > 0)
            {
                enum members = [NormalMemberTuple];
                enum string[] CombinedArray(alias SuperPred, alias MemberPred) = ([
                    staticMap!(MemberPred, NormalMemberTuple)
                ]);
            }
            else
            {
                enum string[] members = null;
                enum string[] CombinedArray(alias SuperPred, alias MemberPred) = null;
            }
        }

        enum string[] useDefaults = CombinedArray!(SuperUseDefault_, MemberUseDefault_);
        enum string[] memberTypes = CombinedArray!(GetSuperTypeAsString_, GetMemberTypeAsString_);
        enum string[] defaults = CombinedArray!(SuperDefault_, MemberDefault_);
        enum string[] attributes = CombinedArray!(SuperAttributes_, MemberAttributes_);

        string[] fields;
        string[] args;
        string[] argexprs;
        string[] defaultAssignments;
        bool[] fieldUseDefault;
        string[] fieldDefault;
        string[] fieldAttributes;
        string[] types;
        string[] directInitFields;
        int[] directInitIndex;
        bool[] directInitUseSelf;

        foreach (i; aliasSeqOf!(members.length.iota))
        {
            enum member = members[i];

            mixin(`alias Type = ` ~ memberTypes[i] ~ `;`);
            mixin(`enum bool useDefault = ` ~ useDefaults[i] ~ `;`);

            bool includeMember = false;

            enum isNullable = is(Type: Nullable!Arg, Arg);

            static if (!isNullable)
            {
                enum bool dupExpr = needToDup!Type;
                enum bool passExprAsConst = dupExpr && __traits(compiles, { Type value = const(Type).init.dup; });
            }
            else
            {
                // unpack nullable for dup
                enum bool dupExpr = needToDup!(typeof(Type.init.get));
                enum bool passExprAsConst = dupExpr && __traits(compiles, { Type value = const(Type).init.get.dup; });
            }

            enum scopeAttributes = [__traits(getFunctionAttributes, {
                static if (passExprAsConst) { const Type parameter = Type.init; }
                else { Type parameter = Type.init; }

                static if (isNullable) { auto value = parameter.get; }
                else { auto value = parameter; }

                static if (dupExpr)
                {
                    Type dupped = value.dup;
                }
            })];
            constructorAttributes = constructorAttributes.filterCanFind(scopeAttributes);

            bool forSuper = false;

            static if (i < argsPassedToSuper)
            {
                includeMember = true;
                forSuper = true;
            }
            else
            {
                mixin("alias symbol = typeof(this)." ~ member ~ ";");

                static assert (is(typeof(symbol)) && !__traits(isTemplate, symbol)); /* must have a resolvable type */

                import boilerplate.util: isStatic;

                includeMember = !mixin(isStatic(member));

                static if (udaIndex!(This.Init, __traits(getAttributes, symbol)) != -1)
                {
                    enum udaFieldIndex = udaIndex!(This.Init, __traits(getAttributes, symbol));
                    alias initArg = Alias!(__traits(getAttributes, symbol)[udaFieldIndex].value);
                    enum lambdaWithSelf = __traits(compiles, initArg(typeof(this).init));
                    enum nakedLambda = __traits(compiles, initArg());

                    directInitFields ~= member;
                    directInitIndex ~= udaFieldIndex;
                    directInitUseSelf ~= __traits(compiles,
                        __traits(getAttributes, symbol)[udaFieldIndex].value(typeof(this).init));
                    includeMember = false;

                    static if (lambdaWithSelf)
                    {
                        static if (__traits(compiles, initArg!(typeof(this))))
                        {
                            enum lambdaAttributes = [__traits(getFunctionAttributes, initArg!(typeof(this)))];
                        }
                        else
                        {
                            enum lambdaAttributes = [__traits(getFunctionAttributes, initArg)];
                        }
                        constructorAttributes = constructorAttributes.filterCanFind(lambdaAttributes);
                    }
                    else static if (nakedLambda)
                    {
                        enum lambdaAttributes = [__traits(getFunctionAttributes, initArg)];

                        constructorAttributes = constructorAttributes.filterCanFind(lambdaAttributes);
                    }
                }

                static if (udaIndex!(This.Exclude, __traits(getAttributes, symbol)) != -1)
                {
                    includeMember = false;
                }
            }

            if (!includeMember) continue;

            enum paramName = optionallyRemoveTrailingUnderline!member;

            string argexpr = paramName;

            if (dupExpr)
            {
                constructorAttributes = constructorAttributes.filter!(q{a != "@nogc"}).array;

                static if (isNullable)
                {
                    argexpr = format!`%s.isNull ? %s.init : %s(%s.get.dup)`
                        (argexpr, memberTypes[i], memberTypes[i], argexpr);
                }
                else
                {
                    argexpr = format!`%s.dup`(argexpr);
                }
            }

            fields ~= member;
            args ~= paramName;
            argexprs ~= argexpr;
            fieldUseDefault ~= useDefault;
            fieldDefault ~= defaults[i];
            fieldAttributes ~= attributes[i];
            defaultAssignments ~= useDefault ? (` = ` ~ defaults[i]) : ``;
            types ~= passExprAsConst ? (`const ` ~ memberTypes[i]) : memberTypes[i];
        }

        size_t establishParameterRank(size_t i)
        {
            // parent explicit, our explicit, our implicit, parent implicit
            const fieldOfParent = i < argsPassedToSuper;
            return fieldUseDefault[i] * 2 + (fieldUseDefault[i] == fieldOfParent);
        }

        auto constructorFieldOrder = fields.length.iota.array.bucketSort(&establishParameterRank);

        assert(fields.length == types.length);
        assert(fields.length == fieldUseDefault.length);
        assert(fields.length == fieldDefault.length);

        result ~= format!`
            public static alias ConstructorInfo =
                saveConstructorInfo!(%s, %-(%s, %));`
        (
            fields.reorder(constructorFieldOrder),
            zip(
                types.reorder(constructorFieldOrder),
                fieldUseDefault.reorder(constructorFieldOrder),
                fieldDefault.reorder(constructorFieldOrder),
                fieldAttributes.reorder(constructorFieldOrder),
            )
            .map!(q{format!`ConstructorField!(%s, %s, %s, %s)`(a[0], a[1], a[2], a[3])})
            .array
        );

        // don't emit this(a = b, c = d) for structs -
        // the compiler complains that it collides with this(), which is reserved.
        if (is(typeof(this) == struct) && fieldUseDefault.all)
        {
            // If there are fields, their direct-construction types may diverge from ours
            // specifically, see the "struct with only default fields" test below
            if (!fields.empty)
            {
                result ~= `static assert(
                    is(typeof(this.tupleof) == ConstructorInfo.Types),
                    "Structs with fields, that are all default, cannot use GenerateThis when their " ~
                    "constructor types would diverge from their native types: " ~
                    typeof(this).stringof ~ ".this" ~ typeof(this.tupleof).stringof ~ ", " ~
                    "but generated constructor would have been " ~ typeof(this).stringof ~ ".this"
                    ~ ConstructorInfo.Types.stringof
                );`;
            }
        }
        else
        {
            result ~= visibility ~ ` this(`
                ~ constructorFieldOrder.mapFormat!`%s %s%s`(types, args, defaultAssignments).join(`, `)
                ~ format!`) %-(%s %)`(constructorAttributes);

            result ~= `{`;

            static if (is(typeof(typeof(super).ConstructorInfo)))
            {
                result ~= `super(` ~ args[0 .. argsPassedToSuper].join(", ") ~ `);`;
            }

            result ~= fields.length.iota.drop(argsPassedToSuper).mapFormat!`this.%s = %s;`(fields, argexprs).join;

            foreach (i, field; directInitFields)
            {
                if (directInitUseSelf[i])
                {
                    result ~= format!`this.%s = __traits(getAttributes, this.%s)[%s].value(this);`
                        (field, field, directInitIndex[i]);
                }
                else
                {
                    result ~= format!`this.%s = __traits(getAttributes, this.%s)[%s].value;`
                        (field, field, directInitIndex[i]);
                }
            }

            result ~= `}`;

            result ~= `protected static enum string[] GeneratedConstructorAttributes_ = [`
                ~ constructorAttributes.map!(q{`"` ~ a ~ `"`}).join(`, `)
                ~ `];`;
        }

        result ~= visibility ~ ` static struct BuilderType(alias T = typeof(this))
        {
            import boilerplate.builder : BuilderImpl;

            mixin BuilderImpl!T;
        }`;

        result ~= visibility ~ ` static auto Builder()()
        {
            return BuilderType!()();
        }`;

        result ~= visibility ~ ` auto BuilderFrom()() const
        {
            import boilerplate.util : optionallyRemoveTrailingUnderline;

            auto builder = BuilderType!()();

            static foreach (field; ConstructorInfo.fields)
            {
                mixin("builder." ~ optionallyRemoveTrailingUnderline!field ~ " = this." ~ field ~ ";");
            }
            return builder;
        }`;

        return result;
    }
}

public template ConstructorField(Type_, bool useDefault_, alias fieldDefault_, attributes_...)
{
    public alias Type = Type_;
    public enum useDefault = useDefault_;
    public alias fieldDefault = fieldDefault_;
    public alias attributes = attributes_;
}

public template saveConstructorInfo(string[] fields_, Fields...)
if (fields_.length == Fields.length
    && allSatisfy!(ApplyLeft!(isInstanceOf, ConstructorField), Fields))
{
    import std.format : format;

    public enum fields = fields_;

    private template FieldInfo_() {
        static foreach (i, field; fields)
        {
            mixin(format!q{public alias %s = Fields[%s];}(field, i));
        }
    }

    public alias FieldInfo = FieldInfo_!();

    mixin(
        format!q{public alias Types = AliasSeq!(%-(%s, %)); }
            (fields.map!(field => format!"FieldInfo.%s.Type"(field)).array));
}

enum ThisEnum
{
    Private,
    Protected,
    Exclude
}

struct This
{
    enum Private = ThisEnum.Private;
    enum Protected = ThisEnum.Protected;
    struct Package
    {
        string packageMask = null;
    }
    enum Exclude = ThisEnum.Exclude;

    // construct with value
    static struct Init(alias Alias)
    {
        static if (__traits(compiles, Alias()))
        {
            @property static auto value() { return Alias(); }
        }
        else
        {
            alias value = Alias;
        }
    }

    static struct Default(alias Alias)
    {
        static if (__traits(compiles, Alias()))
        {
            @property static auto value() { return Alias(); }
        }
        else
        {
            alias value = Alias;
        }
    }
}

public template getUDADefaultOrNothing(T, attributes...)
{
    import boilerplate.util : udaIndex;

    template EnumTest()
    {
        enum EnumTest = attributes[udaIndex!(This.Default, attributes)].value;
    }

    static if (udaIndex!(This.Default, attributes) == -1)
    {
        enum getUDADefaultOrNothing = 0;
    }
    // @(This.Default)
    else static if (__traits(isSame, attributes[udaIndex!(This.Default, attributes)], This.Default))
    {
        enum getUDADefaultOrNothing = T.init;
    }
    else static if (__traits(compiles, EnumTest!()))
    {
        enum getUDADefaultOrNothing = attributes[udaIndex!(This.Default, attributes)].value;
    }
    else
    {
        @property static auto getUDADefaultOrNothing()
        {
            return attributes[udaIndex!(This.Default, attributes)].value;
        }
    }
}

@("struct with only default fields cannot use GenerateThis unless the default this() type matches the generated one")
unittest
{
    static assert(!__traits(compiles, {
        struct Foo
        {
            @(This.Default)
            int[] array;

            mixin(GenerateThis);
        }

        // because you would be able to do
        // const array = [2];
        // auto foo = Foo(array);
        // which would be an error, but work with a generated constructor
        // however, no constructor could be generated, as it would collide with this()
    }));

    // This works though.
    struct Bar
    {
        @(This.Default)
        const int[] array;

        mixin(GenerateThis);
    }

    const array = [2];
    auto bar = Bar(array);
}

@("very large types can be used")
unittest
{
    import std.format : format;
    import std.range : iota;

    struct VeryLargeType
    {
        static foreach (i; 500.iota)
        {
            mixin(format!"int v%s;"(i));
        }

        mixin(GenerateThis);
    }

    struct Wrapper
    {
        VeryLargeType field;

        mixin(GenerateThis);
    }

    auto builder = Wrapper.Builder();
}

@("const nullable assignment")
unittest
{
    import std.typecons : Nullable;

    // non-reference type
    struct Foo
    {
    }

    struct Bar
    {
        Nullable!Foo foo;

        mixin(GenerateThis);
    }

    auto builder = Bar.Builder();

    // trigger assignment bug where dmd tries to roundtrip over const(Foo), implicitly triggering .get
    // avoided by additional assignment overload in the Nullable case
    builder.foo = Nullable!(const Foo)();
}

// can't strip const, because int[] is a reference type and precludes it
@("const nullable assignment with reference type")
unittest
{
    import std.typecons : Nullable, nullable;

    struct Foo
    {
        int[] reference;
    }

    struct Bar
    {
        Nullable!Foo foo;

        mixin(GenerateThis);
    }

    auto builder = Bar.Builder();

    int[] array = [2];
    auto foo = Foo(array);

    // direct assignment still works
    static assert(__traits(compiles, { builder.foo = foo.nullable; }));
    // but const assignment is blocked by opAssign(U)
    static assert(!__traits(compiles, { builder.foo = (cast(const) foo).nullable; }));
}

@("nullable null assignment to buildable field")
unittest
{
    import std.typecons : Nullable;

    struct Foo
    {
        mixin(GenerateThis);
    }

    struct Bar
    {
        Nullable!Foo foo;

        mixin(GenerateThis);
    }

    auto builder = Bar.Builder();

    builder.foo = Nullable!Foo();

    builder.value.shouldEqual(Bar(Nullable!Foo()));
}

// helper to avoid lambda, std.algorithm use in heavily-reused mixin GenerateThisTemplate
public string[] filterCanFind(string[] array, string[] other)
{
    import std.algorithm : canFind, filter;

    return array.filter!(a => other.canFind(a)).array;
}

// ditto
public string[] mapFormat(string fmt, Range, T...)(Range range, T args)
{
    import std.algorithm : map;
    import std.format : format;
    import std.range : iota, join;

    enum argElements = T.length.iota.map!(k => format!"args[%s][i]"(k)).join(", ");

    return range.map!((i) {
        return mixin("format!fmt(" ~ argElements ~ ")");
    }).array;
}
