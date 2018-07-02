module boilerplate.constructor;

import std.algorithm : map;
import std.range : array;
import std.typecons : Tuple;

version(unittest)
{
    import unit_threaded.should;
}

/++
GenerateThis is a mixin string that automatically generates a this() function, customizable with UDA.
+/
public enum string GenerateThis = `
    import boilerplate.constructor: BuilderImpl, GenerateThisTemplate, getUDADefaultOrNothing, removeTrailingUnderlines;
    import boilerplate.util: formatNamed, udaIndex;
    import std.meta : AliasSeq;
    import std.format : format;
    import std.string : replace;
    import std.traits : isNested;
    import std.typecons : Nullable;
    mixin GenerateThisTemplate;
    mixin(typeof(this).generateThisImpl());
`;

///
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

///
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

///
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

///
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

///
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

///
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

///
@("creates no constructor for an empty struct")
unittest
{
    struct Struct
    {
        mixin(GenerateThis);
    }

    auto strct = Struct();
}

///
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

///
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

///
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

///
@("can initialize with immutable arrays")
unittest
{
    class Class
    {
        immutable(Object)[] array;

        mixin(GenerateThis);
    }
}

///
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

    class PublicClass
    {
        mixin(GenerateThis);
    }

    static assert(__traits(getProtection, PrivateClass.__ctor) == "private");
    static assert(__traits(getProtection, ProtectedClass.__ctor) == "protected");
    static assert(__traits(getProtection, PackageClass.__ctor) == "package");
    static assert(__traits(getProtection, PublicClass.__ctor) == "public");
}

///
@("can use default tag with new")
unittest
{
    class Class
    {
        @(This.Default!(() => new Object))
        Object foo;

        mixin(GenerateThis);
    }

    ((new Class).foo !is null).shouldBeTrue;
}

///
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

///
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

///
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

///
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

///
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

///
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

///
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
            return build;
        }
    }();

    with (obj)
    {
        field1.shouldEqual(1);
        field2.shouldEqual(2);
        field3.shouldEqual(3);
    }
}

///
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
            return build;
        }
    }();

    with (obj)
    {
        field1.shouldEqual(2);
        field2.shouldEqual(3);
        field3.shouldEqual(1);
    }
}

///
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
            return build;
        }
    }();

    with (obj)
    {
        field1.shouldEqual(1);
        field2.shouldEqual(5);
        field3.shouldEqual(3);
    }
}

///
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
            return build;
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

///
@("Class.build creates builder and passes it, which is more compact")
unittest
{
    struct Struct
    {
        int field1;
        int field2;
        int field3;

        mixin(GenerateThis);
    }

    auto value = Struct.build!((builder) {
        builder.field1 = 1;
        builder.field2 = 3;
        builder.field3 = 5;
    });

    static assert(is(typeof(value) == Struct));

    with (value)
    {
        field1.shouldEqual(1);
        field2.shouldEqual(3);
        field3.shouldEqual(5);
    }
}

///
@("builder strips trailing underlines")
unittest
{
    struct Struct
    {
        private int a_;

        mixin(GenerateThis);
    }

    auto value = Struct.build!((builder) {
        builder.a = 1;
    });

    value.shouldEqual(Struct(1));
}

///
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

    auto value = Struct2.build!((builder) {
        import std.typecons : Nullable;

        static assert(is(typeof(builder.struct1) == Struct1.Builder));

        builder.struct1.a = 1;
        builder.struct1.b = 2;
        builder.c = 3;
        builder.d = 4;
    });

    static assert(is(typeof(value) == Struct2));

    with (value)
    {
        struct1.a.shouldEqual(1);
        struct1.b.shouldEqual(2);
        c.shouldEqual(3);
        d.shouldEqual(4);
    }
}

///
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

    auto value = Struct2.build!((builder) {
        builder.c = 1;
        builder.d = 2;
    });

    value.shouldEqual(Struct2(1, 2, Struct1(3, 4)));
}

import std.string : format;

enum GetSuperTypeAsString_(size_t Index) = format!`typeof(super).ConstructorInfo.Types[%s]`(Index);

enum GetMemberTypeAsString_(string Member) = format!`typeof(this.%s)`(Member);

enum SuperDefault_(size_t Index) = format!`typeof(super).ConstructorInfo.defaults[%s]`(Index);

enum MemberDefault_(string Member) =
    format!`getUDADefaultOrNothing!(__traits(getAttributes, this.%s))`(Member);

mixin template GenerateThisTemplate()
{
    private static generateThisImpl()
    {
        if (!__ctfe)
        {
            return null;
        }

        import boilerplate.constructor : GetMemberTypeAsString_, GetSuperTypeAsString_,
            MemberDefault_, SuperDefault_, This, removeTrailingUnderline;
        import boilerplate.util : GenNormalMemberTuple, bucketSort, needToDup, reorder, udaIndex;
        import std.algorithm : canFind, filter, map;
        import std.meta : Alias, aliasSeqOf, staticMap;
        import std.range : array, drop, iota;
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
                static if (uda == This.Package)
                {
                    visibility = "package";
                }
                static if (uda == This.Private)
                {
                    visibility = "private";
                }
            }
        }

        enum MemberUseDefault(string Member)
            = mixin(format!(`udaIndex!(This.Default, __traits(getAttributes, this.%s)) != -1`)(Member));

        string[] attributes = ["pure", "nothrow", "@safe", "@nogc"];

        static if (is(typeof(typeof(super).ConstructorInfo)))
        {
            enum argsPassedToSuper = typeof(super).ConstructorInfo.fields.length;
            enum members = typeof(super).ConstructorInfo.fields ~ [NormalMemberTuple];
            enum useDefaults = typeof(super).ConstructorInfo.useDefaults
                ~ [staticMap!(MemberUseDefault, NormalMemberTuple)];
            enum CombinedArray(alias SuperPred, alias MemberPred) = [
                staticMap!(SuperPred, aliasSeqOf!(typeof(super).ConstructorInfo.Types.length.iota)),
                staticMap!(MemberPred, NormalMemberTuple)
            ];
            attributes = typeof(super).GeneratedConstructorAttributes_;
        }
        else
        {
            enum argsPassedToSuper = 0;
            static if (NormalMemberTuple.length > 0)
            {
                enum members = [NormalMemberTuple];
                enum useDefaults = [staticMap!(MemberUseDefault, NormalMemberTuple)];
                enum CombinedArray(alias SuperPred, alias MemberPred) = [staticMap!(MemberPred, NormalMemberTuple)];
            }
            else
            {
                enum string[] members = null;
                enum bool[] useDefaults = null;
                enum string[] CombinedArray(alias SuperPred, alias MemberPred) = null;
            }
        }

        enum string[] memberTypes = CombinedArray!(GetSuperTypeAsString_, GetMemberTypeAsString_);
        enum string[] defaults = CombinedArray!(SuperDefault_, MemberDefault_);

        bool[] passAsConst;
        string[] fields;
        string[] args;
        string[] argexprs;
        string[] defaultAssignments;
        bool[] fieldUseDefault;
        string[] fieldDefault;
        string[] types;
        string[] directInitFields;
        int[] directInitIndex;
        bool[] directInitUseSelf;

        foreach (i; aliasSeqOf!(members.length.iota))
        {
            enum member = members[i];

            mixin(`alias Type = ` ~ memberTypes[i] ~ `;`);

            bool includeMember = false;

            enum isNullable = mixin(format!`is(%s: Nullable!Args, Args...)`(memberTypes[i]));

            static if (!isNullable)
            {
                bool dupExpr = needToDup!Type;
                bool passExprAsConst = dupExpr && __traits(compiles, const(Type).init.dup);
            }
            else
            {
                // unpack nullable for dup
                bool dupExpr = needToDup!(typeof(Type.init.get));
                bool passExprAsConst = dupExpr && __traits(compiles, Type(const(Type).init.get.dup));
            }

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

                includeMember = true;

                if (mixin(isStatic(member)))
                {
                    includeMember = false;
                }

                static if (udaIndex!(This.Init, __traits(getAttributes, symbol)) != -1)
                {
                    enum udaFieldIndex = udaIndex!(This.Init, __traits(getAttributes, symbol));
                    alias initArg = Alias!(__traits(getAttributes, symbol)[udaFieldIndex].value);
                    enum lambdaWithSelf = __traits(compiles, initArg(typeof(this).init));
                    enum nakedLambda = __traits(compiles, initArg());

                    directInitFields ~= member;
                    directInitIndex ~= udaFieldIndex;
                    directInitUseSelf ~= lambdaWithSelf;
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

                        attributes = attributes.filter!(a => lambdaAttributes.canFind(a)).array;
                    }
                    else static if (nakedLambda)
                    {
                        enum lambdaAttributes = [__traits(getFunctionAttributes, initArg)];

                        attributes = attributes.filter!(a => lambdaAttributes.canFind(a)).array;
                    }
                }

                static if (udaIndex!(This.Exclude, __traits(getAttributes, symbol)) != -1)
                {
                    includeMember = false;
                }
            }

            if (!includeMember) continue;

            string paramName = member.removeTrailingUnderline;

            string argexpr = paramName;

            if (dupExpr)
            {
                attributes = attributes.filter!(a => a != "@nogc").array;

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

            passAsConst ~= passExprAsConst;
            fields ~= member;
            args ~= paramName;
            argexprs ~= argexpr;
            fieldUseDefault ~= useDefaults[i];
            fieldDefault ~= defaults[i];
            defaultAssignments ~= useDefaults[i] ? (` = ` ~ defaults[i]) : ``;
            types ~= passExprAsConst ? (`const ` ~ memberTypes[i]) : memberTypes[i];
        }

        size_t establishParameterRank(size_t i)
        {
            // parent explicit, our explicit, our implicit, parent implicit
            const fieldOfParent = i < argsPassedToSuper;
            return useDefaults[i] * 2 + (useDefaults[i] == fieldOfParent);
        }

        auto constructorFieldOrder = fields.length.iota.array.bucketSort(&establishParameterRank);

        result ~= format!`
            public static alias ConstructorInfo =
                saveConstructorInfo!(%s, %s, %-(%s, %)).withDefaults!(%-(%s, %));`
        (
            fields.reorder(constructorFieldOrder),
            fieldUseDefault.reorder(constructorFieldOrder),
            types.reorder(constructorFieldOrder),
            fieldDefault.reorder(constructorFieldOrder)
        );

        if (!(is(typeof(this) == struct) && fields.length == 0)) // don't emit this() for structs
        {
            result ~= visibility ~ ` this(`
                ~ constructorFieldOrder
                    .map!(i => format!`%s %s%s`(types[i], args[i], defaultAssignments[i]))
                    .join(`, `)
                ~ format!`) %-(%s %)`(attributes);

            result ~= `{`;

            static if (is(typeof(typeof(super).ConstructorInfo)))
            {
                result ~= `super(` ~ args[0 .. argsPassedToSuper].join(", ") ~ `);`;
            }

            result ~= fields.length.iota.drop(argsPassedToSuper)
                .map!(i => format!`this.%s = %s;`(fields[i], argexprs[i]))
                .join;

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
                ~ attributes.map!(a => `"` ~ a ~ `"`).join(`, `)
                ~ `];`;
        }

        result ~= `mixin boilerplate.constructor.BuilderImpl!(typeof(this));`;

        return result;
    }
}

public template saveConstructorInfo(string[] fields_, bool[] useDefaults_, Types_...)
{
    template withDefaults(defaults_...)
    {
        static assert(fields_.length == useDefaults.length);
        static assert(fields_.length == Types.length);
        static assert(fields_.length == defaults.length);

        public enum fields = fields_;
        public enum useDefaults = useDefaults_;
        public alias Types = Types_;
        public alias defaults = defaults_;
    }
}

enum ThisEnum
{
    Private,
    Protected,
    Package,
    Exclude
}

struct This
{
    enum Private = ThisEnum.Private;
    enum Protected = ThisEnum.Protected;
    enum Package = ThisEnum.Package;
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

public template getUDADefaultOrNothing(attributes...)
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

public mixin template BuilderImpl(T)
{
    static if (!isNested!T)
    {
        public static T build(alias fill)()
        {
            Builder builder = Builder();

            fill(&builder);
            return builder.build();
        }

        enum builderFields = T.ConstructorInfo.fields.removeTrailingUnderlines;

        public static struct Builder
        {
            static assert(__traits(hasMember, T, "ConstructorInfo"));

            private alias Info = Tuple!(string, "builderField");

            template BuilderFieldInfo(int i)
            {
                alias BaseType = T.ConstructorInfo.Types[i];

                static if (__traits(hasMember, BaseType, "Builder"))
                {
                    alias Type = BaseType.Builder;
                    enum isBuilder = true;
                }
                else
                {
                    alias Type = Nullable!BaseType;
                    enum isBuilder = false;
                }
            }

            static foreach (i, builderField; builderFields)
            {
                mixin(formatNamed!q{public BuilderFieldInfo!i.Type %(builderField);}.values(Info(builderField)));
            }

            this(T value)
            {
                static foreach (i, field; T.ConstructorInfo.fields)
                {
                    mixin(formatNamed!q{
                        static if (__traits(compiles, value.%(valueField)))
                        {
                            static if (BuilderFieldInfo!i.isBuilder)
                            {
                                this.%(builderField) = typeof(this.%(builderField))(value.%(valueField));
                            }
                            else
                            {
                                this.%(builderField) = value.%(valueField);
                            }
                        }
                    }.values(Info(builderFields[i]) ~ Tuple!(string, "valueField")(field)));
                }
            }

            this(Builder builder)
            {
                static foreach (i, builderField; builderFields)
                {
                    mixin(formatNamed!q{
                        static if (BuilderFieldInfo!i.isBuilder)
                        {
                            this.%(builderField) = typeof(this.%(builderField))(builder.%(builderField));
                        }
                        else
                        {
                            if (!builder.%(builderField).isNull)
                            {
                                this.%(builderField) = builder.%(builderField);
                            }
                        }
                    }.values(Info(builderField)));
                }
            }

            public bool isValid() const
            {
                return getError().isNull;
            }

            bool allNull() const
            {
                static foreach (i, builderField; builderFields)
                {
                    mixin(formatNamed!q{
                        static if (BuilderFieldInfo!i.isBuilder)
                        {
                            if (!this.%(builderField).allNull)
                            {
                                return false;
                            }
                        }
                        else
                        {
                            if (!this.%(builderField).isNull)
                            {
                                return false;
                            }
                        }
                    }.values(Info(builderField)));
                }

                return true;
            }

            public Nullable!string getError() const
            {
                static foreach (i, builderField; builderFields)
                {
                    mixin(formatNamed!q{
                        static if (BuilderFieldInfo!i.isBuilder)
                        {
                            // if all fields of builder are null, a default value is permissible.
                            if (!(this.%(builderField).allNull && T.ConstructorInfo.useDefaults[i]))
                            {
                                auto subError = this.%(builderField).getError;

                                if (!subError.isNull)
                                {
                                    return subError;
                                }
                            }
                        }
                        else
                        {
                            static if (!T.ConstructorInfo.useDefaults[i])
                            {
                                if (this.%(builderField).isNull)
                                {
                                    return Nullable!string("required field '%(builderField)' not set in builder!");
                                }
                            }
                        }
                    }.values(Info(builderField)));
                }
                return Nullable!string();
            }

            T build()
            in
            {
                assert(isValid);
            }
            do
            {
                import std.algorithm : map;
                import std.range : array;

                T.ConstructorInfo.Types args = T.ConstructorInfo.Types.init;

                static foreach (i, builderField; builderFields)
                {
                    mixin(formatNamed!q{
                        static if (BuilderFieldInfo!i.isBuilder)
                        {
                            if (this.%(builderField).allNull)
                            {
                                static if (T.ConstructorInfo.useDefaults[i])
                                {
                                    args[i] = T.ConstructorInfo.defaults[i];
                                }
                                else
                                {
                                    assert(false, "isValid/build do not match 1");
                                }
                            }
                            else
                            {
                                args[i] = this.%(builderField).build;
                            }
                        }
                        else
                        {
                            if (!this.%(builderField).isNull)
                            {
                                args[i] = this.%(builderField);
                            }
                            else
                            {
                                static if (T.ConstructorInfo.useDefaults[i])
                                {
                                    args[i] = T.ConstructorInfo.defaults[i];
                                }
                                else
                                {
                                    assert(false, "isValid/build do not match 2");
                                }
                            }
                        }
                    }.values(Info(builderField)));
                }

                static if (is(T == class))
                {
                    return new T(args);
                }
                else
                {
                    return T(args);
                }
            }
        }
    }
}

public alias removeTrailingUnderlines = array => array.map!removeTrailingUnderline.array;

public string removeTrailingUnderline(string name)
{
    import std.string : endsWith;

    return name.endsWith("_") ? name[0 .. $ - 1] : name;
}
