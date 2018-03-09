module boilerplate.constructor;

version(unittest)
{
    import unit_threaded.should;
}

/++
GenerateThis is a mixin string that automatically generates a this() function, customizable with UDA.
+/
public enum string GenerateThis = `
    import boilerplate.constructor: GenerateThisTemplate, Default, getUDADefaultOrNothing;
    import boilerplate.util: udaIndex;
    import std.meta : AliasSeq;
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
        @Default!5
        int value = 5;

        mixin(GenerateThis);
    }

    auto obj1 = new Class();

    obj1.value.shouldEqual(5);

    auto obj2 = new Class(6);

    obj2.value.shouldEqual(6);
}

///
@("properly generates new default values on each call")
unittest
{
    import std.conv : to;

    class Class
    {
        @Default!(() => new Object)
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

        @Default!2
        int field2 = 2;

        mixin(GenerateThis);
    }

    class Child : Parent
    {
        int field3;

        @Default!4
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
        @Default!(() => new Object)
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

import std.string : format;

enum GetSuperTypeAsString_(size_t Index) = format!`typeof(super).GeneratedConstructorTypes_[%s]`(Index);

enum GetMemberTypeAsString_(string Member) = format!`typeof(this.%s)`(Member);

enum SuperDefault_(size_t Index) = format!`typeof(super).GeneratedConstructorDefaults_[%s]`(Index);

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
            MemberDefault_, SuperDefault_, This;
        import boilerplate.util : GenNormalMemberTuple, bucketSort, needToDup, udaIndex;
        import std.meta : aliasSeqOf, staticMap;
        import std.range : array, drop, iota;
        import std.string : endsWith, format, join;
        import std.typecons : Nullable;

        mixin GenNormalMemberTuple;

        string result = null;

        string visibility = "public";

        foreach (uda; __traits(getAttributes, typeof(this)))
        {
            static if (is(typeof(uda) == This))
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
            = mixin(format!`udaIndex!(Default, __traits(getAttributes, this.%s)) != -1`(Member));

        static if (is(typeof(typeof(super).GeneratedConstructorFields_)))
        {
            enum argsPassedToSuper = typeof(super).GeneratedConstructorFields_.length;
            enum members = typeof(super).GeneratedConstructorFields_ ~ [NormalMemberTuple];
            enum useDefaults = typeof(super).GeneratedConstructorUseDefaults_
                ~ [staticMap!(MemberUseDefault, NormalMemberTuple)];
            enum CombinedArray(alias SuperPred, alias MemberPred) = [
                staticMap!(SuperPred, aliasSeqOf!(typeof(super).GeneratedConstructorTypes_.length.iota)),
                staticMap!(MemberPred, NormalMemberTuple)
            ];
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

        enum memberTypes = CombinedArray!(GetSuperTypeAsString_, GetMemberTypeAsString_);
        enum defaults = CombinedArray!(SuperDefault_, MemberDefault_);

        bool[] passAsConst;
        string[] fields;
        string[] quotedFields;
        string[] args;
        string[] argexprs;
        string[] defaultAssignments;
        string[] useDefaultsStr;
        string[] types;

        foreach (i; aliasSeqOf!(members.length.iota))
        {
            enum member = members[i];

            mixin(`alias Type = ` ~ memberTypes[i] ~ `;`);

            bool includeMember = false;

            enum isNullable = mixin(format!`is(%s: Template!Args, alias Template = Nullable, Args...)`(memberTypes[i]));

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
                mixin("alias symbol = this." ~ member ~ ";");

                static assert (is(typeof(symbol)) && !__traits(isTemplate, symbol)); /* must have a resolvable type */

                import boilerplate.util: isStatic;

                includeMember = true;

                if (mixin(isStatic(member)))
                {
                    includeMember = false;
                }

                static if (udaIndex!(This.Exclude, __traits(getAttributes, symbol)) != -1)
                {
                    includeMember = false;
                }
            }

            if (!includeMember) continue;

            string paramName;

            if (member.endsWith("_"))
            {
                paramName = member[0 .. $ - 1];
            }
            else
            {
                paramName = member;
            }

            string argexpr = paramName;

            if (dupExpr)
            {
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
            quotedFields ~= `"` ~ member ~ `"`;
            args ~= paramName;
            argexprs ~= argexpr;
            defaultAssignments ~= useDefaults[i] ? (` = ` ~ defaults[i]) : ``;
            useDefaultsStr ~= useDefaults[i] ? `true` : `false`;
            types ~= passExprAsConst ? (`const ` ~ memberTypes[i]) : memberTypes[i];
        }

        result ~= visibility ~ ` this(`;

        int establishParameterRank(size_t i)
        {
            // parent explicit, our explicit, our implicit, parent implicit
            const fieldOfParent = i < argsPassedToSuper;
            return useDefaults[i] * 2 + (useDefaults[i] == fieldOfParent);
        }

        foreach (k, i; fields.length.iota.array.bucketSort(&establishParameterRank))
        {
            auto type = types[i];

            if (k > 0)
            {
                result ~= `, `;
            }

            result ~= type ~ ` ` ~ args[i] ~ defaultAssignments[i];
        }

        result ~= `) pure nothrow @safe {`;

        static if (is(typeof(typeof(super).GeneratedConstructorFields_)))
        {
            result ~= `super(` ~ args[0 .. argsPassedToSuper].join(", ") ~ `);`;
        }

        foreach (i; fields.length.iota.drop(argsPassedToSuper))
        {
            auto field = fields[i];
            auto argexpr = argexprs[i];

            result ~= `this.` ~ field ~ ` = ` ~ argexpr ~ `;`;
        }

        result ~= `}`;

        result ~= `protected static enum string[] GeneratedConstructorFields_ = [`
            ~ quotedFields.join(`, `)
            ~ `];`;

        result ~= `protected static alias GeneratedConstructorTypes_ = AliasSeq!(`
            ~ types.join(`, `)
            ~ `);`;

        result ~= `protected static enum bool[] GeneratedConstructorUseDefaults_ = [`
            ~ useDefaultsStr.join(`, `)
            ~ `];`;

        result ~= `protected static alias GeneratedConstructorDefaults_ = AliasSeq!(`
            ~ defaults.join(`, `)
            ~ `);`;

        return result;
    }
}

struct Default(alias Alias)
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

enum This
{
    Private,
    Protected,
    Package,
    Exclude
}

private size_t udaDefaultIndex(alias Symbol)()
{
    enum numTraits = __traits(getAttributes, Symbol).length;

    static if (numTraits == 0)
    {
        return -1;
    }
    else
    {
        foreach (i, uda; __traits(getAttributes, Symbol))
        {
            static if (is(uda: Template!Args, alias Template = Default, Args...))
            {
                return i;
            }
            else static if (i == numTraits - 1)
            {
                return -1;
            }
        }
    }
}

public template getUDADefaultOrNothing(attributes...)
{
    import boilerplate.util : udaIndex;

    template EnumTest()
    {
        enum EnumTest = attributes[udaIndex!(Default, attributes)].value;
    }

    static if (udaIndex!(Default, attributes) == -1)
    {
        enum getUDADefaultOrNothing = 0;
    }
    else static if (__traits(compiles, EnumTest!()))
    {
        enum getUDADefaultOrNothing = attributes[udaIndex!(Default, attributes)].value;
    }
    else
    {
        @property static auto getUDADefaultOrNothing()
        {
            return attributes[udaIndex!(Default, attributes)].value;
        }
    }
}
