module boilerplate.autostring;

import std.format : format;
import std.meta : Alias;
import std.traits : Unqual;

version(unittest)
{
    import std.conv : to;
    import std.datetime : SysTime;
    import unit_threaded.should;
}

/++
GenerateToString is a mixin string that automatically generates toString functions,
both sink-based and classic, customizable with UDA annotations on classes, members and functions.
+/
public enum string GenerateToString = `
    import boilerplate.autostring : GenerateToStringTemplate;
    mixin GenerateToStringTemplate;
    mixin(typeof(this).generateToStringErrCheck());
    mixin(typeof(this).generateToStringImpl());
`;

/++
When used with objects, toString methods of type string toString() are also created.
+/
@("generates legacy toString on objects")
unittest
{
    class Class
    {
        mixin(GenerateToString);
    }

    (new Class).to!string.shouldEqual("Class()");
    (new Class).toString.shouldEqual("Class()");
}

/++
A trailing underline in member names is removed when labeling.
+/
@("removes trailing underline")
unittest
{
    struct Struct
    {
        int a_;
        mixin(GenerateToString);
    }

    Struct.init.to!string.shouldEqual("Struct(a=0)");
}

/++
The `@(ToString.Exclude)` tag can be used to exclude a member.
+/
@("can exclude a member")
unittest
{
    struct Struct
    {
        @(ToString.Exclude)
        int a;
        mixin(GenerateToString);
    }

    Struct.init.to!string.shouldEqual("Struct()");
}

/++
The `@(ToString.Optional)` tag can be used to include a member only if it's in some form "present".
This means non-empty for arrays, non-null for objects, non-zero for ints.
+/
@("can optionally exclude member")
unittest
{
    import std.typecons : Nullable, nullable;

    class Class
    {
        mixin(GenerateToString);
    }

    struct Test // some type that is not comparable to null or 0
    {
        mixin(GenerateToString);
    }

    struct Struct
    {
        @(ToString.Optional)
        int a;

        @(ToString.Optional)
        string s;

        @(ToString.Optional)
        Class obj;

        @(ToString.Optional)
        Nullable!Test nullable;

        mixin(GenerateToString);
    }

    Struct.init.to!string.shouldEqual("Struct()");
    Struct(2, "hi", new Class, Test().nullable).to!string
        .shouldEqual(`Struct(a=2, s="hi", obj=Class(), nullable=Test())`);
    Struct(0, "", null, Nullable!Test()).to!string.shouldEqual("Struct()");
}

/++
The `@(ToString.Optional)` tag can be used with a condition parameter
indicating when the type is to be _included._
+/
@("can pass exclusion condition to Optional")
unittest
{
    struct Struct
    {
        @(ToString.Optional!(a => a > 3))
        int i;

        mixin(GenerateToString);
    }

    Struct.init.to!string.shouldEqual("Struct()");
    Struct(3).to!string.shouldEqual("Struct()");
    Struct(5).to!string.shouldEqual("Struct(i=5)");
}

/++
The `@(ToString.Include)` tag can be used to explicitly include a member.
This is intended to be used on property methods.
+/
@("can include a method")
unittest
{
    struct Struct
    {
        @(ToString.Include)
        int foo() const { return 5; }
        mixin(GenerateToString);
    }

    Struct.init.to!string.shouldEqual("Struct(foo=5)");
}

/++
The `@(ToString.Unlabeled)` tag will omit a field's name.
+/
@("can omit names")
unittest
{
    struct Struct
    {
        @(ToString.Unlabeled)
        int a;
        mixin(GenerateToString);
    }

    Struct.init.to!string.shouldEqual("Struct(0)");
}

/++
Parent class `toString()` methods are included automatically as the first entry, except if the parent class is `Object`.
+/
@("can be used in both parent and child class")
unittest
{
    class ParentClass { mixin(GenerateToString); }

    class ChildClass : ParentClass { mixin(GenerateToString); }

    (new ChildClass).to!string.shouldEqual("ChildClass(ParentClass())");
}

@("invokes manually implemented parent toString")
unittest
{
    class ParentClass
    {
        override string toString() const
        {
            return "Some string";
        }
    }

    class ChildClass : ParentClass { mixin(GenerateToString); }

    (new ChildClass).to!string.shouldEqual("ChildClass(Some string)");
}

@("can partially override toString in child class")
unittest
{
    class ParentClass
    {
        mixin(GenerateToString);
    }

    class ChildClass : ParentClass
    {
        override string toString() const
        {
            return "Some string";
        }

        mixin(GenerateToString);
    }

    (new ChildClass).to!string.shouldEqual("Some string");
}

@("invokes manually implemented string toString in same class")
unittest
{
    class Class
    {
        override string toString() const
        {
            return "Some string";
        }

        mixin(GenerateToString);
    }

    (new Class).to!string.shouldEqual("Some string");
}

@("invokes manually implemented void toString in same class")
unittest
{
    class Class
    {
        void toString(scope void delegate(const(char)[]) sink) const
        {
            sink("Some string");
        }

        mixin(GenerateToString);
    }

    (new Class).to!string.shouldEqual("Some string");
}

/++
Inclusion of parent class `toString()` can be prevented using `@(ToString.ExcludeSuper)`.
+/
@("can suppress parent class toString()")
unittest
{
    class ParentClass { }

    @(ToString.ExcludeSuper)
    class ChildClass : ParentClass { mixin(GenerateToString); }

    (new ChildClass).to!string.shouldEqual("ChildClass()");
}

/++
The `@(ToString.Naked)` tag will omit the name of the type and parentheses.
+/
@("can omit the type name")
unittest
{
    @(ToString.Naked)
    struct Struct
    {
        int a;
        mixin(GenerateToString);
    }

    Struct.init.to!string.shouldEqual("a=0");
}

/++
Fields with the same name (ignoring capitalization) as their type, are unlabeled by default.
+/
@("does not label fields with the same name as the type")
unittest
{
    struct Struct1 { mixin(GenerateToString); }

    struct Struct2
    {
        Struct1 struct1;
        mixin(GenerateToString);
    }

    Struct2.init.to!string.shouldEqual("Struct2(Struct1())");
}

@("does not label fields with the same name as the type, even if they're const")
unittest
{
    struct Struct1 { mixin(GenerateToString); }

    struct Struct2
    {
        const Struct1 struct1;
        mixin(GenerateToString);
    }

    Struct2.init.to!string.shouldEqual("Struct2(Struct1())");
}

/++
This behavior can be prevented by explicitly tagging the field with `@(ToString.Labeled)`.
+/
@("does label fields tagged as labeled")
unittest
{
    struct Struct1 { mixin(GenerateToString); }

    struct Struct2
    {
        @(ToString.Labeled)
        Struct1 struct1;
        mixin(GenerateToString);
    }

    Struct2.init.to!string.shouldEqual("Struct2(struct1=Struct1())");
}

/++
Fields of type 'SysTime' and name 'time' are unlabeled by default.
+/
@("does not label SysTime time field correctly")
unittest
{
    struct Struct { SysTime time; mixin(GenerateToString); }

    Struct strct;
    strct.time = SysTime.fromISOExtString("2003-02-01T11:55:00Z");

    // see unittest/config/string.d
    strct.to!string.shouldEqual("Struct(2003-02-01T11:55:00Z)");
}

/++
Fields named 'id' are unlabeled only if they define their own toString().
+/
@("does not label id fields with toString()")
unittest
{
    struct IdType
    {
        string toString() const { return "ID"; }
    }

    struct Struct
    {
        IdType id;
        mixin(GenerateToString);
    }

    Struct.init.to!string.shouldEqual("Struct(ID)");
}

/++
Otherwise, they are labeled as normal.
+/
@("labels id fields without toString")
unittest
{
    struct Struct
    {
        int id;
        mixin(GenerateToString);
    }

    Struct.init.to!string.shouldEqual("Struct(id=0)");
}

/++
Fields that are arrays with a name that is the pluralization of the array base type are also unlabeled by default,
as long as the array is NonEmpty. Otherwise, there would be no way to tell what the field contains.
+/
@("does not label fields named a plural of the basetype, if the type is an array")
unittest
{
    import boilerplate.conditions : NonEmpty;

    struct Value { mixin(GenerateToString); }
    struct Entity { mixin(GenerateToString); }
    struct Day { mixin(GenerateToString); }

    struct Struct
    {
        @NonEmpty
        Value[] values;

        @NonEmpty
        Entity[] entities;

        @NonEmpty
        Day[] days;

        mixin(GenerateToString);
    }

    auto value = Struct(
        [Value()],
        [Entity()],
        [Day()]);

    value.to!string.shouldEqual("Struct([Value()], [Entity()], [Day()])");
}

@("does not label fields named a plural of the basetype, if the type is a BitFlags")
unittest
{
    import std.typecons : BitFlags;

    enum Flag
    {
        A = 1 << 0,
        B = 1 << 1,
    }

    struct Struct
    {
        BitFlags!Flag flags;

        mixin(GenerateToString);
    }

    auto value = Struct(BitFlags!Flag(Flag.A, Flag.B));

    value.to!string.shouldEqual("Struct(Flag(A, B))");
}

/++
Fields that are not NonEmpty are always labeled.
This is because they can be empty, in which case you can't tell what's in them from naming.
+/
@("does label fields that may be empty")
unittest
{
    import boilerplate.conditions : NonEmpty;

    struct Value { mixin(GenerateToString); }

    struct Struct
    {
        Value[] values;

        mixin(GenerateToString);
    }

    Struct(null).to!string.shouldEqual("Struct(values=[])");
}

/++
`GenerateToString` can be combined with `GenerateFieldAccessors` without issue.
+/
@("does not collide with accessors")
unittest
{
    struct Struct
    {
        import boilerplate.accessors : ConstRead, GenerateFieldAccessors;

        @ConstRead
        private int a_;

        mixin(GenerateFieldAccessors);

        mixin(GenerateToString);
    }

    Struct.init.to!string.shouldEqual("Struct(a=0)");
}

@("supports child classes of abstract classes")
unittest
{
    static abstract class ParentClass
    {
    }
    class ChildClass : ParentClass
    {
        mixin(GenerateToString);
    }
}

@("supports custom toString handlers")
unittest
{
    struct Struct
    {
        @ToStringHandler!(i => i ? "yes" : "no")
        int i;

        mixin(GenerateToString);
    }

    Struct.init.to!string.shouldEqual("Struct(i=no)");
}

@("passes nullable unchanged to custom toString handlers")
unittest
{
    import std.typecons : Nullable;

    struct Struct
    {
        @ToStringHandler!(ni => ni.isNull ? "no" : "yes")
        Nullable!int ni;

        mixin(GenerateToString);
    }

    Struct.init.to!string.shouldEqual("Struct(ni=no)");
}

// see unittest.config.string
@("supports optional BitFlags in structs")
unittest
{
    import std.typecons : BitFlags;

    enum Enum
    {
        A = 1,
        B = 2,
    }

    struct Struct
    {
        @(ToString.Optional)
        BitFlags!Enum field;

        mixin(GenerateToString);
    }

    Struct.init.to!string.shouldEqual("Struct()");
}

@("prints hashmaps in deterministic order")
unittest
{
    struct Struct
    {
        string[string] map;

        mixin(GenerateToString);
    }

    bool foundCollision = false;

    foreach (key1; ["opstop", "opsto"])
    {
        enum key2 = "foo"; // collide

        const first = Struct([key1: null, key2: null]);
        string[string] backwardsHashmap;

        backwardsHashmap[key2] = null;
        backwardsHashmap[key1] = null;

        const second = Struct(backwardsHashmap);

        if (first.map.keys != second.map.keys)
        {
            foundCollision = true;
            first.to!string.shouldEqual(second.to!string);
        }
    }
    assert(foundCollision, "none of the listed keys caused a hash collision");
}

@("applies custom formatters to types in hashmaps")
unittest
{
    import std.datetime : SysTime;

    struct Struct
    {
        SysTime[string] map;

        mixin(GenerateToString);
    }

    const expected = "2003-02-01T11:55:00Z";
    const value = Struct(["foo": SysTime.fromISOExtString(expected)]);

    value.to!string.shouldEqual(`Struct(map=["foo": ` ~ expected ~ `])`);
}

@("can format associative array of Nullable SysTime")
unittest
{
    import std.datetime : SysTime;
    import std.typecons : Nullable;

    struct Struct
    {
        Nullable!SysTime[string] map;

        mixin(GenerateToString);
    }

    const expected = `Struct(map=["foo": null])`;
    const value = Struct(["foo": Nullable!SysTime()]);

    value.to!string.shouldEqual(expected);
}

@("can format associative array of type that cannot be sorted")
unittest
{
    import std.datetime : SysTime;
    import std.typecons : Nullable;

    struct Struct
    {
        mixin(GenerateToString);
    }

    struct Struct2
    {
        bool[Struct] hashmap;

        mixin(GenerateToString);
    }

    const expected = `Struct2(hashmap=[])`;
    const value = Struct2(null);

    value.to!string.shouldEqual(expected);
}

@("labels nested types with fully qualified names")
unittest
{
    import std.datetime : SysTime;
    import std.typecons : Nullable;

    struct Struct
    {
        struct Struct2
        {
            mixin(GenerateToString);
        }

        Struct2 struct2;

        mixin(GenerateToString);
    }

    const expected = `Struct(Struct.Struct2())`;
    const value = Struct(Struct.Struct2());

    value.to!string.shouldEqual(expected);
}

@("supports fully qualified names with quotes")
unittest
{
    import std.datetime : SysTime;
    import std.typecons : Nullable;

    struct Struct(string s)
    {
        struct Struct2
        {
            mixin(GenerateToString);
        }

        Struct2 struct2;

        mixin(GenerateToString);
    }

    const expected = `Struct!"foo"(Struct!"foo".Struct2())`;
    const value = Struct!"foo"(Struct!"foo".Struct2());

    value.to!string.shouldEqual(expected);
}

mixin template GenerateToStringTemplate()
{

    // this is a separate function to reduce the
    // "warning: unreachable code" spam that is falsely created from static foreach
    private static generateToStringErrCheck()
    {
        if (!__ctfe)
        {
            return null;
        }

        import boilerplate.autostring : ToString, typeName;
        import boilerplate.util : GenNormalMemberTuple;
        import std.string : format;

        bool udaIncludeSuper;
        bool udaExcludeSuper;

        foreach (uda; __traits(getAttributes, typeof(this)))
        {
            static if (is(typeof(uda) == ToString))
            {
                switch (uda)
                {
                    case ToString.IncludeSuper: udaIncludeSuper = true; break;
                    case ToString.ExcludeSuper: udaExcludeSuper = true; break;
                    default: break;
                }
            }
        }

        if (udaIncludeSuper && udaExcludeSuper)
        {
            return format!(`static assert(false, ` ~
                `"Contradictory tags on '" ~ %(%s%) ~ "': IncludeSuper and ExcludeSuper");`)
                ([typeName!(typeof(this))]);
        }

        mixin GenNormalMemberTuple!true;

        foreach (member; NormalMemberTuple)
        {
            enum error = checkAttributeConsistency!(__traits(getAttributes, __traits(getMember, typeof(this), member)));

            static if (error)
            {
                return format!error(member);
            }
        }

        return ``;
    }

    private static generateToStringImpl()
    {
        if (!__ctfe)
        {
            return null;
        }

        import boilerplate.autostring : isMemberUnlabeledByDefault, ToString, typeName;
        import boilerplate.conditions : NonEmpty;
        import boilerplate.util : GenNormalMemberTuple, udaIndex;
        import std.meta : Alias;
        import std.string : endsWith, format, split, startsWith, strip;
        import std.traits : BaseClassesTuple, getUDAs, Unqual;

        // synchronized without lock contention is basically free, so always do it
        // TODO enable when https://issues.dlang.org/show_bug.cgi?id=18504 is fixed
        enum synchronize = false && is(typeof(this) == class);

        const constExample = typeof(this).init;
        auto normalExample = typeof(this).init;

        enum alreadyHaveStringToString = __traits(hasMember, typeof(this), "toString")
            && is(typeof(normalExample.toString()) == string);
        enum alreadyHaveUsableStringToString = alreadyHaveStringToString
            && is(typeof(constExample.toString()) == string);

        enum alreadyHaveVoidToString = __traits(hasMember, typeof(this), "toString")
            && is(typeof(normalExample.toString((void delegate(const(char)[])).init)) == void);
        enum alreadyHaveUsableVoidToString = alreadyHaveVoidToString
            && is(typeof(constExample.toString((void delegate(const(char)[])).init)) == void);

        enum isObject = is(typeof(this): Object);

        static if (isObject)
        {
            enum userDefinedStringToString = hasOwnStringToString!(typeof(this), typeof(super));
            enum userDefinedVoidToString = hasOwnVoidToString!(typeof(this), typeof(super));
        }
        else
        {
            enum userDefinedStringToString = alreadyHaveStringToString;
            enum userDefinedVoidToString = alreadyHaveVoidToString;
        }

        static if (userDefinedStringToString && userDefinedVoidToString)
        {
            string result = ``; // Nothing to be done.
        }
        // if the user has defined their own string toString() in this aggregate:
        else static if (userDefinedStringToString)
        {
            // just call it.
            static if (alreadyHaveUsableStringToString)
            {
                string result = `public void toString(scope void delegate(const(char)[]) sink) const {` ~
                    ` sink(this.toString());` ~
                    ` }`;

                static if (isObject
                    && is(typeof(typeof(super).init.toString((void delegate(const(char)[])).init)) == void))
                {
                    result = `override ` ~ result;
                }
            }
            else
            {
                string result = `static assert(false, "toString is not const in this class.");`;
            }
        }
        // if the user has defined their own void toString() in this aggregate:
        else
        {
            string result = null;

            static if (!userDefinedVoidToString)
            {
                bool nakedMode;
                bool udaIncludeSuper;
                bool udaExcludeSuper;

                foreach (uda; __traits(getAttributes, typeof(this)))
                {
                    static if (is(typeof(uda) == ToStringEnum))
                    {
                        switch (uda)
                        {
                            case ToString.Naked: nakedMode = true; break;
                            case ToString.IncludeSuper: udaIncludeSuper = true; break;
                            case ToString.ExcludeSuper: udaExcludeSuper = true; break;
                            default: break;
                        }
                    }
                }

                string NamePlusOpenParen = typeName!(typeof(this)) ~ "(";

                version(AutoStringDebug)
                {
                    result ~= format!`pragma(msg, "%s %s");`(alreadyHaveStringToString, alreadyHaveVoidToString);
                }

                static if (isObject && alreadyHaveVoidToString) result ~= `override `;

                result ~= `public void toString(scope void delegate(const(char)[]) sink) const {`
                    ~ `import boilerplate.autostring: ToStringHandler;`
                    ~ `import boilerplate.util: sinkWrite;`
                    ~ `import std.traits: getUDAs;`;

                static if (synchronize)
                {
                    result ~= `synchronized (this) { `;
                }

                if (!nakedMode)
                {
                    result ~= format!`sink(%(%s%));`([NamePlusOpenParen]);
                }

                bool includeSuper = false;

                static if (isObject)
                {
                    if (alreadyHaveUsableStringToString || alreadyHaveUsableVoidToString)
                    {
                        includeSuper = true;
                    }
                }

                if (udaIncludeSuper)
                {
                    includeSuper = true;
                }
                else if (udaExcludeSuper)
                {
                    includeSuper = false;
                }

                static if (isObject)
                {
                    if (includeSuper)
                    {
                        static if (!alreadyHaveUsableStringToString && !alreadyHaveUsableVoidToString)
                        {
                            return `static assert(false, `
                                ~ `"cannot include super class in GenerateToString: `
                                ~ `parent class has no usable toString!");`;
                        }
                        else {
                            static if (alreadyHaveUsableVoidToString)
                            {
                                result ~= `super.toString(sink);`;
                            }
                            else
                            {
                                result ~= `sink(super.toString());`;
                            }
                            result ~= `bool comma = true;`;
                        }
                    }
                    else
                    {
                        result ~= `bool comma = false;`;
                    }
                }
                else
                {
                    result ~= `bool comma = false;`;
                }

                result ~= `{`;

                mixin GenNormalMemberTuple!(true);

                foreach (member; NormalMemberTuple)
                {
                    mixin("alias symbol = typeof(this)." ~ member ~ ";");

                    enum udaInclude = udaIndex!(ToString.Include, __traits(getAttributes, symbol)) != -1;
                    enum udaExclude = udaIndex!(ToString.Exclude, __traits(getAttributes, symbol)) != -1;
                    enum udaLabeled = udaIndex!(ToString.Labeled, __traits(getAttributes, symbol)) != -1;
                    enum udaUnlabeled = udaIndex!(ToString.Unlabeled, __traits(getAttributes, symbol)) != -1;
                    enum udaOptional = udaIndex!(ToString.Optional, __traits(getAttributes, symbol)) != -1;
                    enum udaToStringHandler = udaIndex!(ToStringHandler, __traits(getAttributes, symbol)) != -1;
                    enum udaNonEmpty = udaIndex!(NonEmpty, __traits(getAttributes, symbol)) != -1;

                    // see std.traits.isFunction!()
                    static if (
                        is(symbol == function)
                        || is(typeof(symbol) == function)
                        || (is(typeof(&symbol) U : U*) && is(U == function)))
                    {
                        enum isFunction = true;
                    }
                    else
                    {
                        enum isFunction = false;
                    }

                    enum includeOverride = udaInclude || udaOptional;

                    enum includeMember = (!isFunction || includeOverride) && !udaExclude;

                    static if (includeMember)
                    {
                        string memberName = member;

                        if (memberName.endsWith("_"))
                        {
                            memberName = memberName[0 .. $ - 1];
                        }

                        bool labeled = true;

                        static if (udaUnlabeled)
                        {
                            labeled = false;
                        }

                        if (isMemberUnlabeledByDefault!(Unqual!(typeof(symbol)))(memberName, udaNonEmpty))
                        {
                            labeled = false;
                        }

                        static if (udaLabeled)
                        {
                            labeled = true;
                        }

                        string membervalue = `this.` ~ member;

                        bool escapeStrings = true;

                        static if (udaToStringHandler)
                        {
                            alias Handlers = getUDAs!(symbol, ToStringHandler);

                            static assert(Handlers.length == 1);

                            static if (__traits(compiles, Handlers[0].Handler(typeof(symbol).init)))
                            {
                                membervalue = `getUDAs!(this.` ~ member ~ `, ToStringHandler)[0].Handler(`
                                    ~ membervalue
                                    ~ `)`;

                                escapeStrings = false;
                            }
                            else
                            {
                                return `static assert(false, "cannot determine how to call ToStringHandler");`;
                            }
                        }

                        string readMemberValue = membervalue;
                        string conditionalWritestmt; // formatted with sink.sinkWrite(... readMemberValue ... )

                        static if (udaOptional)
                        {
                            import std.array : empty;

                            enum optionalIndex = udaIndex!(ToString.Optional, __traits(getAttributes, symbol));
                            alias optionalUda = Alias!(__traits(getAttributes, symbol)[optionalIndex]);

                            static if (is(optionalUda == struct))
                            {
                                conditionalWritestmt = format!q{
                                    if (__traits(getAttributes, %s)[%s].condition(%s)) { %%s }
                                } (membervalue, optionalIndex, membervalue);
                            }
                            else static if (__traits(compiles, typeof(symbol).init.isNull))
                            {
                                conditionalWritestmt = format!q{if (!%s.isNull) { %%s }}
                                    (membervalue);
                                readMemberValue = membervalue ~ ".get";
                            }
                            else static if (__traits(compiles, typeof(symbol).init.empty))
                            {
                                conditionalWritestmt = format!q{import std.array : empty; if (!%s.empty) { %%s }}
                                    (membervalue);
                            }
                            else static if (__traits(compiles, typeof(symbol).init !is null))
                            {
                                conditionalWritestmt = format!q{if (%s !is null) { %%s }}
                                    (membervalue);
                            }
                            else static if (__traits(compiles, typeof(symbol).init != 0))
                            {
                                conditionalWritestmt = format!q{if (%s != 0) { %%s }}
                                    (membervalue);
                            }
                            else static if (__traits(compiles, { if (typeof(symbol).init) { } }))
                            {
                                conditionalWritestmt = format!q{if (%s) { %%s }}
                                    (membervalue);
                            }
                            else
                            {
                                return format!(`static assert(false, `
                                        ~ `"don't know how to figure out whether %s is present.");`)
                                    (member);
                            }
                        }
                        else
                        {
                            conditionalWritestmt = q{ %s };
                        }

                        string writestmt;

                        if (labeled)
                        {
                            writestmt = format!`sink.sinkWrite(comma, %s, "%s=%%s", %s);`
                                (escapeStrings, memberName, readMemberValue);
                        }
                        else
                        {
                            writestmt = format!`sink.sinkWrite(comma, %s, "%%s", %s);`
                                (escapeStrings, readMemberValue);
                        }

                        result ~= format(conditionalWritestmt, writestmt);
                    }
                }

                result ~= `} `;

                if (!nakedMode)
                {
                    result ~= `sink(")");`;
                }

                static if (synchronize)
                {
                    result ~= `} `;
                }

                result ~= `} `;
            }

            // generate fallback string toString()
            // that calls, specifically, *our own* toString impl.
            // (this is important to break cycles when a subclass implements a toString that calls super.toString)
            static if (isObject)
            {
                result ~= `override `;
            }

            result ~= `public string toString() const {`
                ~ `string result;`
                ~ `typeof(this).toString((const(char)[] part) { result ~= part; });`
                ~ `return result;`
            ~ `}`;
        }
        return result;
    }
}

template checkAttributeConsistency(Attributes...)
{
    enum checkAttributeConsistency = checkAttributeHelper();

    private string checkAttributeHelper()
    {
        if (!__ctfe)
        {
            return null;
        }

        import std.string : format;

        bool include, exclude, optional, labeled, unlabeled;

        foreach (uda; Attributes)
        {
            static if (is(typeof(uda) == ToStringEnum))
            {
                switch (uda)
                {
                    case ToString.Include: include = true; break;
                    case ToString.Exclude: exclude = true; break;
                    case ToString.Labeled: labeled = true; break;
                    case ToString.Unlabeled: unlabeled = true; break;
                    default: break;
                }
            }
            else static if (is(uda == struct) && __traits(isSame, uda, ToString.Optional))
            {
                optional = true;
            }
        }

        if (include && exclude)
        {
            return `static assert(false, "Contradictory tags on '%s': Include and Exclude");`;
        }

        if (include && optional)
        {
            return `static assert(false, "Redundant tags on '%s': Optional implies Include");`;
        }

        if (exclude && optional)
        {
            return `static assert(false, "Contradictory tags on '%s': Exclude and Optional");`;
        }

        if (labeled && unlabeled)
        {
            return `static assert(false, "Contradictory tags on '%s': Labeled and Unlabeled");`;
        }

        return null;
    }
}

struct ToStringHandler(alias Handler_)
{
    alias Handler = Handler_;
}

enum ToStringEnum
{
    // these go on the class
    Naked,
    IncludeSuper,
    ExcludeSuper,

    // these go on the field/method
    Unlabeled,
    Labeled,
    Exclude,
    Include,
}

struct ToString
{
    static foreach (name; __traits(allMembers, ToStringEnum))
    {
        mixin(format!q{enum %s = ToStringEnum.%s;}(name, name));
    }

    static struct Optional(alias condition_)
    {
        alias condition = condition_;
    }
}

public bool isMemberUnlabeledByDefault(Type)(string field, bool attribNonEmpty)
{
    import std.datetime : SysTime;
    import std.range.primitives : ElementType, isInputRange;
    import std.typecons : BitFlags;

    field = field.toLower;

    static if (isInputRange!Type)
    {
        alias BaseType = ElementType!Type;

        if (field == BaseType.stringof.toLower.pluralize && attribNonEmpty)
        {
            return true;
        }
    }
    else static if (is(Type: const BitFlags!BaseType, BaseType))
    {
        if (field == BaseType.stringof.toLower.pluralize)
        {
            return true;
        }
    }

    return field == Type.stringof.toLower
        || (field == "time" && is(Type == SysTime))
        || (field == "id" && is(typeof(Type.toString)));
}

private string toLower(string text)
{
    import std.string : stdToLower = toLower;

    string result = null;

    foreach (ub; cast(immutable(ubyte)[]) text)
    {
        if (ub >= 0x80) // utf-8, non-ascii
        {
            return text.stdToLower;
        }
        if (ub >= 'A' && ub <= 'Z')
        {
            result ~= cast(char) (ub + ('a' - 'A'));
        }
        else
        {
            result ~= cast(char) ub;
        }
    }
    return result;
}

// http://code.activestate.com/recipes/82102/
private string pluralize(string label)
{
    import std.algorithm.searching : contain = canFind;

    string postfix = "s";
    if (label.length > 2)
    {
        enum vowels = "aeiou";

        if (label.stringEndsWith("ch") || label.stringEndsWith("sh"))
        {
            postfix = "es";
        }
        else if (auto before = label.stringEndsWith("y"))
        {
            if (!vowels.contain(label[$ - 2]))
            {
                postfix = "ies";
                label = before;
            }
        }
        else if (auto before = label.stringEndsWith("is"))
        {
            postfix = "es";
            label = before;
        }
        else if ("sxz".contain(label[$-1]))
        {
            postfix = "es"; // glasses
        }
    }
    return label ~ postfix;
}

@("has functioning pluralize()")
unittest
{
    "dog".pluralize.shouldEqual("dogs");
    "ash".pluralize.shouldEqual("ashes");
    "day".pluralize.shouldEqual("days");
    "entity".pluralize.shouldEqual("entities");
    "thesis".pluralize.shouldEqual("theses");
    "glass".pluralize.shouldEqual("glasses");
}

private string stringEndsWith(const string text, const string suffix)
{
    import std.range : dropBack;
    import std.string : endsWith;

    if (text.endsWith(suffix))
    {
        return text.dropBack(suffix.length);
    }
    return null;
}

@("has functioning stringEndsWith()")
unittest
{
    "".stringEndsWith("").shouldNotBeNull;
    "".stringEndsWith("x").shouldBeNull;
    "Hello".stringEndsWith("Hello").shouldNotBeNull;
    "Hello".stringEndsWith("Hello").shouldEqual("");
    "Hello".stringEndsWith("lo").shouldEqual("Hel");
}

template hasOwnFunction(Aggregate, Super, string Name, Type)
{
    import std.meta : AliasSeq, Filter;
    import std.traits : Unqual;
    enum FunctionMatchesType(alias Fun) = is(Unqual!(typeof(Fun)) == Type);

    alias MyFunctions = AliasSeq!(__traits(getOverloads, Aggregate, Name));
    alias MatchingFunctions = Filter!(FunctionMatchesType, MyFunctions);
    enum hasFunction = MatchingFunctions.length == 1;

    alias SuperFunctions = AliasSeq!(__traits(getOverloads, Super, Name));
    alias SuperMatchingFunctions = Filter!(FunctionMatchesType, SuperFunctions);
    enum superHasFunction = SuperMatchingFunctions.length == 1;

    static if (hasFunction)
    {
        static if (superHasFunction)
        {
            enum hasOwnFunction = !__traits(isSame, MatchingFunctions[0], SuperMatchingFunctions[0]);
        }
        else
        {
            enum hasOwnFunction = true;
        }
    }
    else
    {
        enum hasOwnFunction = false;
    }
}

/**
 * Find qualified name of `T` including any containing types; not including containing functions or modules.
 */
public template typeName(T)
{
    static if (__traits(compiles, __traits(parent, T)))
    {
        alias parent = Alias!(__traits(parent, T));
        enum isSame = __traits(isSame, T, parent);

        static if (!isSame && (
            is(parent == struct) || is(parent == union) || is(parent == enum) ||
            is(parent == class) || is(parent == interface)))
        {
            enum typeName = typeName!parent ~ "." ~ Unqual!T.stringof;
        }
        else
        {
            enum typeName = Unqual!T.stringof;
        }
    }
    else
    {
        enum typeName = Unqual!T.stringof;
    }
}

private final abstract class StringToStringSample {
    override string toString();
}

private final abstract class VoidToStringSample {
    void toString(scope void delegate(const(char)[]) sink);
}

enum hasOwnStringToString(Aggregate, Super)
    = hasOwnFunction!(Aggregate, Super, "toString", typeof(StringToStringSample.toString));

enum hasOwnVoidToString(Aggregate, Super)
    = hasOwnFunction!(Aggregate, Super, "toString", typeof(VoidToStringSample.toString));

@("correctly recognizes the existence of string toString() in a class")
unittest
{
    class Class1
    {
        override string toString() { return null; }
        static assert(!hasOwnVoidToString!(typeof(this), typeof(super)));
        static assert(hasOwnStringToString!(typeof(this), typeof(super)));
    }

    class Class2
    {
        override string toString() const { return null; }
        static assert(!hasOwnVoidToString!(typeof(this), typeof(super)));
        static assert(hasOwnStringToString!(typeof(this), typeof(super)));
    }

    class Class3
    {
        void toString(scope void delegate(const(char)[]) sink) const { }
        override string toString() const { return null; }
        static assert(hasOwnVoidToString!(typeof(this), typeof(super)));
        static assert(hasOwnStringToString!(typeof(this), typeof(super)));
    }

    class Class4
    {
        void toString(scope void delegate(const(char)[]) sink) const { }
        static assert(hasOwnVoidToString!(typeof(this), typeof(super)));
        static assert(!hasOwnStringToString!(typeof(this), typeof(super)));
    }

    class Class5
    {
        mixin(GenerateToString);
    }

    class ChildClass1 : Class1
    {
        static assert(!hasOwnStringToString!(typeof(this), typeof(super)));
    }

    class ChildClass2 : Class2
    {
        static assert(!hasOwnStringToString!(typeof(this), typeof(super)));
    }

    class ChildClass3 : Class3
    {
        static assert(!hasOwnStringToString!(typeof(this), typeof(super)));
    }

    class ChildClass5 : Class5
    {
        static assert(!hasOwnStringToString!(typeof(this), typeof(super)));
    }
}
