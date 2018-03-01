module boilerplate.conditions;

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
    import std.typecons : Nullable, nullable;

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

mixin template GenerateInvariantsTemplate()
{
    private static string generateInvariantsImpl()
    {
        if (!__ctfe)
        {
            return null;
        }

        import boilerplate.conditions : IsConditionAttribute, generateChecksForAttributes;
        import boilerplate.util : GenNormalMemberTuple;
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
            mixin(`alias symbol = this.` ~ member ~ `;`);

            static if (__traits(compiles, typeof(symbol).init))
            {
                result ~= generateChecksForAttributes!(typeof(symbol),
                        StdMetaFilter!(IsConditionAttribute, __traits(getAttributes, symbol)))
                    (`this.` ~ member);
            }
        }

        result ~= synchronize ? ` }` : ``;

        result ~= ` }`;

        return result;
    }
}

public string generateChecksForAttributes(T, Attributes...)(string member_expression, string info = "")
{
    import boilerplate.conditions : NonEmpty, NonNull;
    import boilerplate.util : udaIndex;
    import std.array : empty;
    import std.string : format;
    import std.traits : ConstOf, isAssociativeArray;
    import std.typecons : Nullable;

    enum isNullable = is(T: Template!Args, alias Template = Nullable, Args...);

    static if (isNullable)
    {
        enum access = `%s.get`;
    }
    else
    {
        enum access = `%s`;
    }

    alias MemberType = typeof(mixin(format!access(`T.init`)));

    string expression = format!access(member_expression);

    enum canFormat = __traits(compiles, format(`%s`, ConstOf!MemberType.init));

    string checks;

    static if (udaIndex!(NonEmpty, Attributes) != -1)
    {
        static if (!__traits(compiles, MemberType.init.empty()))
        {
            return format!`static assert(false, "Cannot call std.array.empty() on '%s'");`(expression);
        }

        static if (canFormat)
        {
            checks ~= format!(`assert(!%s.empty, `
                ~ `format("@NonEmpty: assert(!%s.empty) failed%s: %s = %%s", %s));`)
                (expression, expression, info, expression, expression);
        }
        else
        {
            checks ~= format!`assert(!%s.empty(), "@NonEmpty: assert(!%s.empty) failed%s");`
                (expression, expression, info);
        }
    }

    static if (udaIndex!(NonNull, Attributes) != -1)
    {
        static if (__traits(compiles, MemberType.init.isNull))
        {
            checks ~= format!`assert(!%s.isNull, "@NonNull: assert(!%s.isNull) failed%s");`
                (expression, expression, info);
        }
        else static if (__traits(compiles, MemberType.init !is null))
        {
            // Nothing good can come of printing something that is null.
            checks ~= format!`assert(%s !is null, "@NonNull: assert(%s !is null) failed%s");`
                (expression, expression, info);
        }
        else
        {
            return format!`static assert(false, "Cannot compare '%s' to null");`(expression);
        }
    }

    static if (udaIndex!(NonInit, Attributes) != -1)
    {
        auto reference = `typeof(` ~ expression ~ `).init`;

        if (!__traits(compiles, MemberType.init !is MemberType.init))
        {
            return format!`static assert(false, "Cannot compare '%s' to %s.init");`(expression, MemberType.stringof);
        }

        static if (canFormat)
        {
            checks ~=
                format!(`assert(%s !is %s, `
                    ~ `format("@NonInit: assert(%s !is %s.init) failed%s: %s = %%s", %s));`)
                    (expression, reference, expression, MemberType.stringof, info, expression, expression);
        }
        else
        {
            checks ~=
                format!`assert(%s !is %s, "@NonInit: assert(%s !is %s.init) failed%s");`
                    (expression, reference, expression, MemberType.stringof, info);
        }
    }

    static if (udaIndex!(AllNonNull, Attributes) != -1)
    {
        import std.algorithm: all;

        checks ~= `import std.algorithm: all;`;

        static if (__traits(compiles, MemberType.init.all!"a !is null"))
        {
            static if (canFormat)
            {
                checks ~=
                    format!(`assert(%s.all!"a !is null", format(`
                        ~ `"@AllNonNull: assert(%s.all!\"a !is null\") failed%s: %s = %%s", %s));`)
                        (expression, expression, info, expression, expression);
            }
            else
            {
                checks ~= format!(`assert(%s.all!"a !is null", `
                    ~ `"@AllNonNull: assert(%s.all!\"a !is null\") failed%s");`)
                    (expression, expression, info);
            }
        }
        else static if (__traits(compiles, MemberType.init.all!"!a.isNull"))
        {
            static if (canFormat)
            {
                checks ~=
                    format!(`assert(%s.all!"!a.isNull", format(`
                        ~ `"@AllNonNull: assert(%s.all!\"!a.isNull\") failed%s: %s = %%s", %s));`)
                        (expression, expression, info, expression, expression);
            }
            else
            {
                checks ~= format!(`assert(%s.all!"!a.isNull", `
                    ~ `"@AllNonNull: assert(%s.all!\"!a.isNull\") failed%s");`)
                    (expression, expression, info);
            }
        }
        else static if (__traits(compiles, isAssociativeArray!MemberType))
        {
            enum checkValues = __traits(compiles, MemberType.init.byValue.all!`a !is null`);
            enum checkKeys = __traits(compiles, MemberType.init.byKey.all!"a !is null");

            static if (!checkKeys && !checkValues)
            {
                return format!(`static assert(false, "Neither key nor value of associative array `
                    ~ `'%s' can be checked against null.");`)(expression);
            }

            static if (checkValues)
            {
                checks ~=
                    format!(`assert(%s.byValue.all!"a !is null", `
                        ~ `"@AllNonNull: assert(%s.byValue.all!\"a !is null\") failed%s");`)
                        (expression, expression, info);
            }

            static if (checkKeys)
            {
                checks ~=
                    format!(`assert(%s.byKey.all!"a !is null", `
                        ~ `"@AllNonNull: assert(%s.byKey.all!\"a !is null\") failed%s");`)
                        (expression, expression, info);
            }
        }
        else
        {
            return format!`static assert(false, "Cannot compare all '%s' to null");`(expression);
        }
    }

    if (checks.empty)
    {
        return null;
    }

    static if (isNullable)
    {
        return `if (!` ~ member_expression ~ `.isNull) {` ~ checks ~ `}`;
    }
    else
    {
        return checks;
    }
}

public enum IsConditionAttribute(alias A) = __traits(isSame, A, NonEmpty) || __traits(isSame, A, NonNull)
    || __traits(isSame, A, NonInit) || __traits(isSame, A, AllNonNull);
