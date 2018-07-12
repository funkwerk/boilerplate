module boilerplate.conditions;

import std.typecons;

version(unittest)
{
    import core.exception : AssertError;
    import unit_threaded.should;
}

/++
`GenerateInvariants` is a mixin string that automatically generates an `invariant{}` block
for each field with a condition.
+/
public enum string GenerateInvariants = `
    import boilerplate.conditions : GenerateInvariantsTemplate;
    mixin GenerateInvariantsTemplate;
    mixin(typeof(this).generateInvariantsImpl());
`;

/++
When a field is marked with `@NonEmpty`, `!field.empty` is asserted.
+/
public struct NonEmpty
{
}

///
@("throws when a NonEmpty field is initialized empty")
unittest
{
    class Class
    {
        @NonEmpty
        int[] array_;

        this(int[] array)
        {
            this.array_ = array;
        }

        mixin(GenerateInvariants);
    }

    (new Class(null)).shouldThrow!AssertError;
}

///
@("throws when a NonEmpty field is assigned empty")
unittest
{
    class Class
    {
        @NonEmpty
        private int[] array_;

        this(int[] array)
        {
            this.array_ = array;
        }

        public void array(int[] arrayValue)
        {
            this.array_ = arrayValue;
        }

        mixin(GenerateInvariants);
    }

    (new Class([2])).array(null).shouldThrow!AssertError;
}

/++
When a field is marked with `@NonNull`, `field !is null` is asserted.
+/
public struct NonNull
{
}

///
@("throws when a NonNull field is initialized null")
unittest
{
    class Class
    {
        @NonNull
        Object obj_;

        this(Object obj)
        {
            this.obj_ = obj;
        }

        mixin(GenerateInvariants);
    }

    (new Class(null)).shouldThrow!AssertError;
}

/++
When a field is marked with `@AllNonNull`, `field.all!"a !is null"` is asserted.
+/
public struct AllNonNull
{
}

///
@("throws when an AllNonNull field is initialized with an array containing null")
unittest
{
    class Class
    {
        @AllNonNull
        Object[] objs;

        this(Object[] objs)
        {
            this.objs = objs;
        }

        mixin(GenerateInvariants);
    }

    (new Class(null)).objs.shouldEqual(null);
    (new Class([null])).shouldThrow!AssertError;
    (new Class([new Object, null])).shouldThrow!AssertError;
}

/// `@AllNonNull` may be used with associative arrays.
@("supports AllNonNull on associative arrays")
unittest
{
    class Class
    {
        @AllNonNull
        Object[int] objs;

        this(Object[int] objs)
        {
            this.objs = objs;
        }

        mixin(GenerateInvariants);
    }

    (new Class(null)).objs.shouldEqual(null);
    (new Class([0: null])).shouldThrow!AssertError;
    (new Class([0: new Object, 1: null])).shouldThrow!AssertError;
}

/// When used with associative arrays, `@AllNonNull` may check keys, values or both.
@("supports AllNonNull on associative array keys")
unittest
{
    class Class
    {
        @AllNonNull
        int[Object] objs;

        this(int[Object] objs)
        {
            this.objs = objs;
        }

        mixin(GenerateInvariants);
    }

    (new Class(null)).objs.shouldEqual(null);
    (new Class([null: 0])).shouldThrow!AssertError;
    (new Class([new Object: 0, null: 1])).shouldThrow!AssertError;
}

/++
When a field is marked with `@NonInit`, `field !is T.init` is asserted.
+/
public struct NonInit
{
}

///
@("throws when a NonInit field is initialized with T.init")
unittest
{
    import core.time : Duration;

    class Class
    {
        @NonInit
        float f_;

        this(float f) { this.f_ = f; }

        mixin(GenerateInvariants);
    }

    (new Class(float.init)).shouldThrow!AssertError;
}

/++
When <b>any</b> condition check is applied to a nullable field, the test applies to the value,
if any, contained in the field. The "null" state of the field is ignored.
+/
@("doesn't throw when a Nullable field is null")
unittest
{
    class Class
    {
        @NonInit
        Nullable!float f_;

        this(Nullable!float f)
        {
            this.f_ = f;
        }

        mixin(GenerateInvariants);
    }

    (new Class(5f.nullable)).f_.isNull.shouldBeFalse;
    (new Class(Nullable!float())).f_.isNull.shouldBeTrue;
    (new Class(float.init.nullable)).shouldThrow!AssertError;
}

/++
Conditions can be applied to static attributes, generating static invariants.
+/
@("does not allow invariants on static fields")
unittest
{
    static assert(!__traits(compiles, ()
    {
        class Class
        {
            @NonNull
            private static Object obj;

            mixin(GenerateInvariants);
        }
    }), "invariant on static field compiled when it shouldn't");
}

@("works with classes inheriting from templates")
unittest
{
    interface I(T)
    {
    }

    interface K(T)
    {
    }

    class C : I!ubyte, K!ubyte
    {
    }

    class S
    {
        C c;

        mixin(GenerateInvariants);
    }
}

mixin template GenerateInvariantsTemplate()
{
    private static string generateInvariantsImpl()
    {
        if (!__ctfe)
        {
            return null;
        }

        import boilerplate.conditions : IsConditionAttribute, generateChecksForAttributes;
        import boilerplate.util : GenNormalMemberTuple, isStatic;
        import std.format : format;
        import std.meta : StdMetaFilter = Filter;

        string result = null;

        result ~= `invariant {` ~
            `import std.format : format;` ~
            `import std.array : empty;`;

        // TODO blocked by https://issues.dlang.org/show_bug.cgi?id=18504
        // note: synchronized without lock contention is basically free
        // IMPORTANT! Do not enable this until you have a solution for reliably detecting which attributes actually
        // require synchronization! overzealous synchronize has the potential to lead to needless deadlocks.
        // (consider implementing @GuardedBy)
        enum synchronize = false;

        result ~= synchronize ? `synchronized (this) {` : ``;

        mixin GenNormalMemberTuple;

        foreach (member; NormalMemberTuple)
        {
            mixin(`alias symbol = typeof(this).` ~ member ~ `;`);

            alias ConditionAttributes = StdMetaFilter!(IsConditionAttribute, __traits(getAttributes, symbol));

            static if (mixin(isStatic(member)) && ConditionAttributes.length > 0)
            {
                result ~= format!(`static assert(false, `
                    ~ `"Cannot add constraint on static field %s: no support for static invariants");`
                )(member);
            }

            static if (__traits(compiles, typeof(symbol).init))
            {
                result ~= generateChecksForAttributes!(typeof(symbol), ConditionAttributes)(`this.` ~ member);
            }
        }

        result ~= synchronize ? ` }` : ``;

        result ~= ` }`;

        return result;
    }
}

public string generateChecksForAttributes(T, Attributes...)(string memberExpression, string info = "")
if (Attributes.length == 0)
{
    return null;
}

private alias InfoTuple = Tuple!(string, "expr", string, "info", string, "typename");

public string generateChecksForAttributes(T, Attributes...)(string memberExpression, string info = "")
if (Attributes.length > 0)
{
    import boilerplate.util : formatNamed, udaIndex;
    import std.string : format;
    import std.traits : ConstOf;

    enum isNullable = is(T: Nullable!Args, Args...);

    static if (isNullable)
    {
        enum access = `%s.get`;
    }
    else
    {
        enum access = `%s`;
    }

    alias MemberType = typeof(mixin(isNullable ? `T.init.get` : `T.init`));

    string expression = isNullable ? (memberExpression ~ `.get`) : memberExpression;

    auto values = InfoTuple(expression, info, MemberType.stringof);

    string checks;

    static if (udaIndex!(NonEmpty, Attributes) != -1)
    {
        checks ~= generateNonEmpty!MemberType(values);
    }

    static if (udaIndex!(NonNull, Attributes) != -1)
    {
        checks ~= generateNonNull!MemberType(values);
    }

    static if (udaIndex!(NonInit, Attributes) != -1)
    {
        checks ~= generateNonInit!MemberType(values);
    }

    static if (udaIndex!(AllNonNull, Attributes) != -1)
    {
        checks ~= generateAllNonNull!MemberType(values);
    }

    static if (isNullable)
    {
        return `if (!` ~ memberExpression ~ `.isNull) {` ~ checks ~ `}`;
    }
    else
    {
        return checks;
    }
}

private string generateNonEmpty(T)(InfoTuple values)
{
    import boilerplate.util : formatNamed;
    import std.array : empty;

    string checks;

    static if (!__traits(compiles, T.init.empty()))
    {
        checks ~= formatNamed!`static assert(false, "Cannot call std.array.empty() on '%(expr)'");`.values(values);
    }

    enum canFormat = __traits(compiles, format(`%s`, ConstOf!MemberType.init));

    static if (canFormat)
    {
        checks ~= formatNamed!(`assert(!%(expr).empty, `
            ~ `format("@NonEmpty: assert(!%(expr).empty) failed%(info): %(expr) = %s", %(expr)));`)
            .values(values);
    }
    else
    {
        checks ~= formatNamed!`assert(!%(expr).empty(), "@NonEmpty: assert(!%(expr).empty) failed%(info)");`
            .values(values);
    }

    return checks;
}

private string generateNonNull(T)(InfoTuple values)
{
    import boilerplate.util : formatNamed;

    string checks;

    static if (__traits(compiles, T.init.isNull))
    {
        checks ~= formatNamed!`assert(!%(expr).isNull, "@NonNull: assert(!%(expr).isNull) failed%(info)");`
            .values(values);
    }
    else static if (__traits(compiles, T.init !is null))
    {
        // Nothing good can come of printing something that is null.
        checks ~= formatNamed!`assert(%(expr) !is null, "@NonNull: assert(%(expr) !is null) failed%(info)");`
            .values(values);
    }
    else
    {
        checks ~= formatNamed!`static assert(false, "Cannot compare '%(expr)' to null");`.values(values);
    }

    return checks;
}

private string generateNonInit(T)(InfoTuple values)
{
    import boilerplate.util : formatNamed;

    string checks;

    enum canFormat = __traits(compiles, format(`%s`, ConstOf!MemberType.init));

    static if (!__traits(compiles, T.init !is T.init))
    {
        checks ~= formatNamed!`static assert(false, "Cannot compare '%(expr)' to %(typename).init");`
            .values(values);
    }

    static if (canFormat)
    {
        checks ~= formatNamed!(`assert(%(expr) !is typeof(%(expr)).init, `
            ~ `format("@NonInit: assert(%(expr) !is %(typename).init) failed%(info): %(expr) = %s", %(expr)));`)
            .values(values);
    }
    else
    {
        checks ~= formatNamed!(`assert(%(expr) !is typeof(%(expr)).init, `
            ~ `"@NonInit: assert(%(expr) !is %(typename).init) failed%(info)");`)
            .values(values);
    }

    return checks;
}

private string generateAllNonNull(T)(InfoTuple values)
{
    import boilerplate.util : formatNamed;
    import std.algorithm : all;
    import std.traits : isAssociativeArray;

    string checks;

    enum canFormat = __traits(compiles, format(`%s`, ConstOf!MemberType.init));

    checks ~= `import std.algorithm: all;`;

    static if (__traits(compiles, T.init.all!"a !is null"))
    {
        static if (canFormat)
        {
            checks ~= formatNamed!(`assert(%(expr).all!"a !is null", format(`
                ~ `"@AllNonNull: assert(%(expr).all!\"a !is null\") failed%(info): %(expr) = %s", %(expr)));`)
                .values(values);
        }
        else
        {
            checks ~= formatNamed!(`assert(%(expr).all!"a !is null", `
                ~ `"@AllNonNull: assert(%(expr).all!\"a !is null\") failed%(info)");`)
                .values(values);
        }
    }
    else static if (__traits(compiles, T.init.all!"!a.isNull"))
    {
        static if (canFormat)
        {
            checks ~= formatNamed!(`assert(%(expr).all!"!a.isNull", format(`
                ~ `"@AllNonNull: assert(%(expr).all!\"!a.isNull\") failed%(info): %(expr) = %s", %(expr)));`)
                .values(values);
        }
        else
        {
            checks ~= formatNamed!(`assert(%(expr).all!"!a.isNull", `
                ~ `"@AllNonNull: assert(%(expr).all!\"!a.isNull\") failed%(info)");`)
                .values(values);
        }
    }
    else static if (__traits(compiles, isAssociativeArray!T))
    {
        enum checkValues = __traits(compiles, T.init.byValue.all!`a !is null`);
        enum checkKeys = __traits(compiles, T.init.byKey.all!"a !is null");

        static if (!checkKeys && !checkValues)
        {
            checks ~= formatNamed!(`static assert(false, "Neither key nor value of associative array `
                ~ `'%(expr)' can be checked against null.");`).values(values);
        }

        static if (checkValues)
        {
            checks ~=
                formatNamed!(`assert(%(expr).byValue.all!"a !is null", `
                    ~ `"@AllNonNull: assert(%(expr).byValue.all!\"a !is null\") failed%(info)");`)
                    .values(values);
        }

        static if (checkKeys)
        {
            checks ~=
                formatNamed!(`assert(%(expr).byKey.all!"a !is null", `
                    ~ `"@AllNonNull: assert(%(expr).byKey.all!\"a !is null\") failed%(info)");`)
                    .values(values);
        }
    }
    else
    {
        checks ~= formatNamed!`static assert(false, "Cannot compare all '%(expr)' to null");`.values(values);
    }

    return checks;
}

public enum IsConditionAttribute(alias A) = __traits(isSame, A, NonEmpty) || __traits(isSame, A, NonNull)
    || __traits(isSame, A, NonInit) || __traits(isSame, A, AllNonNull);
