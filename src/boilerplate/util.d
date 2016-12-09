module boilerplate.util;

import std.meta;
import std.traits;

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

    string res = "[";
    foreach (i, member; members)
    {
        if (i > 0) res ~= ", ";

        if (member != "this")
        {
            string check = `__traits(compiles, &typeof(this).init.` ~ member ~ `)`
                ~ ` && __traits(compiles, typeof(typeof(this).init.` ~ member ~ `))`;

            if (!includeFunctions)
            {
                check ~= ` && !is(typeof(typeof(this).` ~ member ~ `) == function)`
                    ~ ` && !is(typeof(&typeof(this).init.` ~ member ~ `) == delegate)`;
            }

            res ~= check;
        }
        else
        {
            res ~= `false`;
        }
    }
    res ~= "]";

    return res;
}

string GenNormalMembersImpl(string[] members, bool[] compiles)
{
    import std.string : join;

    string[] res;

    foreach (i, member; members)
    {
        if (member != "this" && compiles[i])
        {
            res ~= "\"" ~ member ~ "\"";
        }
    }

    return "AliasSeq!(" ~ res.join(", ") ~ ")";
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
                    static if (is(attrib: Template!Args, alias Template = attr, Args...))
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

// a stable, simple O(n) sort optimal for a small number of sort keys
T[] bucketSort(T)(T[] array, int delegate(T) rankfn)
{
    T[][] buckets;

    foreach (element; array)
    {
        auto rank = rankfn(element);

        while (rank >= buckets.length)
        {
            buckets ~= null;
        }

        buckets[rank] ~= element;
    }

    T[] res;

    foreach (bucket; buckets)
    {
        res ~= bucket;
    }

    return res;
}

void sinkWrite(T)(scope void delegate(const(char)[]) sink, ref bool comma, string fmt, T arg)
{
    static assert (__traits(compiles, { import config.string; }),
        "Please define config.string, containing functions of the form"
        ~ " void toString(T, scope void delegate(const(char)[]) sink) const");

    import config.string : customToString = toString;
    import std.datetime : SysTime;
    import std.format : formattedWrite;
    import std.typecons : Nullable;

    alias PlainT = typeof(cast() arg);

    enum isNullable = is(PlainT: Template!Args, alias Template = Nullable, Args...);

    static if (isNullable)
    {
        if (!arg.isNull)
        {
            sinkWrite(sink, comma, fmt, arg.get);
        }
        return;
    }

    static if (is(PlainT == SysTime))
    {
        if (arg == SysTime.init) // crashes on toString
        {
            return;
        }
    }

    if (comma)
    {
        sink(", ");
    }

    comma = true;

    static if (__traits(compiles, customToString(arg, sink)))
    {
        struct TypeWrapper
        {
            void toString(scope void delegate(const(char)[]) sink) const
            {
                customToString(arg, sink);
            }
        }
        sink.formattedWrite(fmt, TypeWrapper());
    }
    else
    {
        sink.formattedWrite(fmt, arg);
    }
}
