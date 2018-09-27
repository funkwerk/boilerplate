module boilerplate.util;

import std.meta;
import std.range : iota;
import std.traits;

static if (__traits(compiles, { import config.string : toString; }))
{
    import config.string : customToString = toString;
}
else
{
    private void customToString(T)()
    if (false)
    {
    }
}

enum needToDup(T) = isArray!(T) && !DeepConst!(T);

enum DeepConst(T) = __traits(compiles, (const T x) { T y = x; });

@("needToDup correctly handles common types")
@nogc nothrow pure @safe unittest
{
    int integerField;
    int[] integerArrayField;

    static assert(!needToDup!(typeof(integerField)));
    static assert(needToDup!(typeof(integerArrayField)));
}

@("needToDup correctly handles const types")
@nogc nothrow pure @safe unittest
{
    const(int)[] constIntegerArrayField;
    string stringField;

    static assert(!needToDup!(typeof(constIntegerArrayField)));
    static assert(!needToDup!(typeof(stringField)));
}

@("doesn't add write-only properties to NormalMembers")
unittest
{
    struct Test
    {
        @property void foo(int i) { }
        mixin GenNormalMemberTuple;
        static assert(is(NormalMemberTuple == AliasSeq!()),
            "write-only properties should not appear in NormalMembers because they have no type"
        );
    }
}

@("doesn't add read properties to NormalMembers if includeFunctions is false")
unittest
{
    struct Test
    {
        @property int foo() { return 0; }
        int bar() { return 0; }
        mixin GenNormalMemberTuple;
        static assert(is(NormalMemberTuple == AliasSeq!()),
            "read properties should not appear in NormalMembers if includeFunctions is false"
        );
    }
}

/**
 * Generate AliasSeq of "normal" members - ie. no templates, no alias, no enum, only fields
 * (and functions if includeFunctions is true).
 */
mixin template GenNormalMemberTuple(bool includeFunctions = false)
{
    import boilerplate.util : GenNormalMembersCheck, GenNormalMembersImpl;
    import std.meta : AliasSeq;

    mixin(`alias NormalMemberTuple = ` ~ GenNormalMembersImpl([__traits(derivedMembers, typeof(this))],
        mixin(GenNormalMembersCheck([__traits(derivedMembers, typeof(this))], includeFunctions))) ~ `;`);
}

string GenNormalMembersCheck(string[] members, bool includeFunctions)
{
    import std.format : format;
    import std.string : join;

    string code = "[";
    foreach (i, member; members)
    {
        if (i > 0)
        {
            code ~= ", "; // don't .map.join because this is compile performance critical code
        }

        if (member != "this")
        {
            string check = `__traits(compiles, &typeof(this).init.` ~ member ~ `)`
                ~ ` && __traits(compiles, typeof(typeof(this).init.` ~ member ~ `))`;

            if (!includeFunctions)
            {
                check ~= ` && !is(typeof(typeof(this).` ~ member ~ `) == function)`
                    ~ ` && !is(typeof(&typeof(this).init.` ~ member ~ `) == delegate)`;
            }

            code ~= check;
        }
        else
        {
            code ~= `false`;
        }
    }
    code ~= "]";

    return code;
}

string GenNormalMembersImpl(string[] members, bool[] compiles)
{
    import std.string : join;

    string[] names;

    foreach (i, member; members)
    {
        if (member != "this" && compiles[i])
        {
            names ~= "\"" ~ member ~ "\"";
        }
    }

    return "AliasSeq!(" ~ names.join(", ") ~ ")";
}

template getOverloadLike(Aggregate, string Name, Type)
{
    alias Overloads = AliasSeq!(__traits(getOverloads, Aggregate, Name));
    enum FunctionMatchesType(alias Fun) = is(typeof(Fun) == Type);
    alias MatchingOverloads = Filter!(FunctionMatchesType, Overloads);

    static assert(MatchingOverloads.length == 1);

    alias getOverloadLike = MatchingOverloads[0];
}

template udaIndex(alias attr, attributes...)
{
    enum udaIndex = helper();

    ptrdiff_t helper()
    {
        if (!__ctfe)
        {
            return 0;
        }
        static if (attributes.length)
        {
            foreach (i, attrib; attributes)
            {
                enum lastAttrib = i == attributes.length - 1;

                static if (__traits(isTemplate, attr))
                {
                    static if (__traits(isSame, attrib, attr))
                    {
                        return i;
                    }
                    else static if (is(attrib: attr!Args, Args...))
                    {
                        return i;
                    }
                    else static if (lastAttrib)
                    {
                        return -1;
                    }
                }
                else static if (__traits(compiles, is(typeof(attrib) == typeof(attr)) && attrib == attr))
                {
                    static if (is(typeof(attrib) == typeof(attr)) && attrib == attr)
                    {
                        return i;
                    }
                    else static if (lastAttrib)
                    {
                        return -1;
                    }
                }
                else static if (__traits(compiles, typeof(attrib)) && __traits(compiles, is(typeof(attrib) == attr)))
                {
                    static if (is(typeof(attrib) == attr))
                    {
                        return i;
                    }
                    else static if (lastAttrib)
                    {
                        return -1;
                    }
                }
                else static if (__traits(compiles, is(attrib == attr)))
                {
                    static if (is(attrib == attr))
                    {
                        return i;
                    }
                    else static if (lastAttrib)
                    {
                        return -1;
                    }
                }
                else static if (lastAttrib)
                {
                    return -1;
                }
            }
        }
        else
        {
            return -1;
        }
    }
}

string isStatic(string field)
{
    return `__traits(getOverloads, typeof(this), "` ~ field ~ `").length == 0`
      ~ ` && __traits(compiles, &this.` ~ field ~ `)`;
}

string isUnsafe(string field)
{
    return isStatic(field) ~ ` && !__traits(compiles, () @safe { return this.` ~ field ~ `; })`;
}

// a stable, simple O(n) sort optimal for a small number of sort keys
T[] bucketSort(T)(T[] inputArray, size_t delegate(T) rankfn)
{
    import std.algorithm : joiner;
    import std.range : array;

    T[][] buckets;

    foreach (element; inputArray)
    {
        auto rank = rankfn(element);

        if (rank >= buckets.length)
        {
            buckets.length = rank + 1;
        }

        buckets[rank] ~= element;
    }

    return buckets.joiner.array;
}

void sinkWrite(T...)(scope void delegate(const(char)[]) sink, ref bool comma, bool escapeStrings, string fmt, T args)
{
    import std.algorithm : map;
    import std.datetime : SysTime;
    import std.format : format, formattedWrite;
    import std.string : join;
    import std.typecons : Nullable;

    static if (T.length == 1) // check for optional field: single Nullable
    {
        const arg = args[0];

        alias PlainT = typeof(cast() arg);

        enum isNullable = is(PlainT: Nullable!Arg, Arg);
    }
    else
    {
        enum isNullable = false;
    }

    static if (isNullable)
    {
        if (!arg.isNull)
        {
            sink.sinkWrite(comma, escapeStrings, fmt, arg.get);
        }
        return;
    }
    else
    {
        auto replaceArg(int i)()
        if (i >= 0 && i < T.length)
        {
            alias PlainT = typeof(cast() args[i]);

            static if (is(PlainT == SysTime))
            {
                static struct SysTimeInitWrapper
                {
                    const typeof(args[i]) arg;

                    void toString(scope void delegate(const(char)[]) sink) const
                    {
                        if (this.arg is SysTime.init) // crashes on toString
                        {
                            sink("SysTime.init");
                        }
                        else
                        {
                            wrapFormatType(this.arg, false).toString(sink);
                        }
                    }
                }

                return SysTimeInitWrapper(args[i]);
            }
            else
            {
                return wrapFormatType(args[i], escapeStrings);
            }
        }

        if (comma)
        {
            sink(", ");
        }

        comma = true;

        mixin(`sink.formattedWrite(fmt, ` ~ T.length.iota.map!(i => format!"replaceArg!%s"(i)).join(", ") ~ `);`);
    }
}

private auto wrapFormatType(T)(T value, bool escapeStrings)
{
    import std.traits : isSomeString;

    static if (__traits(compiles, customToString(value, (void delegate(const(char)[])).init)))
    {
        static struct CustomToStringWrapper
        {
            T value;

            void toString(scope void delegate(const(char)[]) sink) const
            {
                customToString(this.value, sink);
            }
        }
        return CustomToStringWrapper(value);
    }
    else static if (is(T : V[K], K, V))
    {
        return orderedAssociativeArray(value);
    }
    else static if (isSomeString!T)
    {
        static struct QuoteStringWrapper
        {
            T value;

            bool escapeStrings;

            void toString(scope void delegate(const(char)[]) sink) const
            {
                import std.format : formattedWrite;
                import std.range : only;

                if (escapeStrings)
                {
                    sink.formattedWrite!"%(%s%)"(this.value.only);
                }
                else
                {
                    sink.formattedWrite!"%s"(this.value);
                }
            }
        }

        return QuoteStringWrapper(value, escapeStrings);
    }
    else
    {
        return value;
    }
}

private auto orderedAssociativeArray(T : V[K], K, V)(T associativeArray)
{
    static struct OrderedAssociativeArray
    {
        T associativeArray;

        public void toString(scope void delegate(const(char)[]) sink) const
        {
            import std.algorithm : sort;
            sink("[");

            bool comma = false;

            foreach (key; this.associativeArray.keys.sort)
            {
                sink.sinkWrite(comma, true, "%s: %s", key, this.associativeArray[key]);
            }
            sink("]");
        }
    }

    return OrderedAssociativeArray(associativeArray);
}

private string quote(string text)
{
    import std.string : replace;

    return `"` ~ text.replace(`\`, `\\`).replace(`"`, `\"`) ~ `"`;
}

private string genFormatFunctionImpl(string text)
{
    import std.algorithm : findSplit;
    import std.exception : enforce;
    import std.format : format;
    import std.range : empty;
    import std.string : join;

    string[] fragments;

    string remainder = text;

    while (true)
    {
        auto splitLeft = remainder.findSplit("%(");

        if (splitLeft[1].empty)
        {
            break;
        }

        auto splitRight = splitLeft[2].findSplit(")");

        enforce(!splitRight[1].empty, format!"Closing paren not found in '%s'"(remainder));
        remainder = splitRight[2];

        fragments ~= quote(splitLeft[0]);
        fragments ~= splitRight[0];
    }
    fragments ~= quote(remainder);

    return `string values(T)(T arg)
    {
        with (arg)
        {
            return ` ~ fragments.join(" ~ ") ~ `;
        }
    }`;
}

public template formatNamed(string text)
{
    mixin(genFormatFunctionImpl(text));
}

///
@("formatNamed replaces named keys with given values")
unittest
{
    import std.typecons : tuple;
    import unit_threaded.should;

    formatNamed!("Hello %(second) World %(first)%(second)!")
        .values(tuple!("first", "second")("3", "5"))
        .shouldEqual("Hello 5 World 35!");
}

public T[] reorder(T)(T[] source, size_t[] newOrder)
in
{
    import std.algorithm : sort;
    import std.range : array, iota;

    // newOrder must be a permutation of source indices
    assert(newOrder.dup.sort.array == source.length.iota.array);
}
body
{
    import std.algorithm : map;
    import std.range : array;

    return newOrder.map!(i => source[i]).array;
}

@("reorder returns reordered array")
unittest
{
    import unit_threaded.should;

    [1, 2, 3].reorder([0, 2, 1]).shouldEqual([1, 3, 2]);
}

// TODO replace with Nullable once pr 19037 is merged
public struct Optional(T)
{
    import std.typecons : Nullable;

    // workaround: types in union are not destructed
    union DontCallDestructor { SafeUnqual!T t; }

    // workaround: types in struct are memcpied in move/moveEmplace, bypassing constness
    struct UseMemcpyMove { DontCallDestructor u; }

    private UseMemcpyMove value = UseMemcpyMove.init;

    public bool isNull = true;

    public this(T value)
    {
        this.value = UseMemcpyMove(DontCallDestructor(value));
        this.isNull = false;
    }

    // This method should only be called from Builder.value! Builder fields are semantically write-only.
    public inout(T) _get() inout
    in
    {
        assert(!this.isNull);
    }
    do
    {
        return this.value.u.t;
    }

    public void opAssign(T value)
    {
        import std.algorithm : moveEmplace, move;

        auto valueCopy = UseMemcpyMove(DontCallDestructor(value));

        if (this.isNull)
        {
            moveEmplace(valueCopy, this.value);

            this.isNull = false;
        }
        else
        {
            move(valueCopy, this.value);
        }
    }

    public void opOpAssign(string op, RHS)(RHS rhs)
    if (__traits(compiles, mixin("T.init " ~ op ~ " RHS.init")))
    {
        if (this.isNull)
        {
            this = T.init;
        }
        mixin("this = this._get " ~ op ~ " rhs;");
    }

    static if (is(T: Nullable!Arg, Arg))
    {
        public void opAssign(Arg value)
        {
            this = T(value);
        }
    }

    static if (is(T == struct) && hasElaborateDestructor!T)
    {
        ~this()
        {
            if (!this.isNull)
            {
                destroy(this.value.u.t);
            }
        }
    }
}

///
unittest
{
    Optional!(int[]) intArrayOptional;

    assert(intArrayOptional.isNull);

    intArrayOptional ~= 5;

    assert(!intArrayOptional.isNull);
    assert(intArrayOptional._get == [5]);

    intArrayOptional ~= 6;

    assert(intArrayOptional._get == [5, 6]);
}

private template SafeUnqual(T)
{
    static if (__traits(compiles, (T t) { Unqual!T ut = t; }))
    {
        alias SafeUnqual = Unqual!T;
    }
    else
    {
        alias SafeUnqual = T;
    }
}

public string removeTrailingUnderline(string name)
{
    import std.string : endsWith;

    return name.endsWith("_") ? name[0 .. $ - 1] : name;
}
