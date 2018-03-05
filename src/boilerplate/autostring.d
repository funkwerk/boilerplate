module boilerplate.autostring;

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
    class Class
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
        mixin(GenerateToString);
    }

    Struct.init.to!string.shouldEqual("Struct()");
    Struct(2, "hi", new Class).to!string.shouldEqual("Struct(a=2, s=hi, obj=Class())");
    Struct(0, "", null).to!string.shouldEqual("Struct()");
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
Fields that are arrays with a name that is the pluralization of the array base type are also unlabeled by default.
+/
@("does not label fields with the same name as the type")
unittest
{
    struct SomeValue { mixin(GenerateToString); }
    struct Entity { mixin(GenerateToString); }
    struct Day { mixin(GenerateToString); }

    struct Struct
    {
        SomeValue[] someValues;
        Entity[] entities;
        Day[] days;
        mixin(GenerateToString);
    }

    Struct.init.to!string.shouldEqual("Struct([], [], [])");
}

/++
`GenerateToString` can be combined with `GenerateFieldAccessors` without issue.
+/
@("does not collide with accessors")
unittest
{
    struct Struct
    {
        import boilerplate.accessors : GenerateFieldAccessors, ConstRead;

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

        import boilerplate.autostring : ToString;
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
            return format!`static assert(false, "Contradictory tags on '%s': IncludeSuper and ExcludeSuper");`
                (typeof(this).stringof);
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

        import std.string : endsWith, format, split, startsWith, strip;
        import std.traits : BaseClassesTuple, Unqual, getUDAs;
        import boilerplate.autostring : ToString, isMemberUnlabeledByDefault;
        import boilerplate.util : GenNormalMemberTuple, udaIndex;

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
                    static if (is(typeof(uda) == ToString))
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

                string NamePlusOpenParen = Unqual!(typeof(this)).stringof ~ "(";

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
                    result ~= `sink("` ~ NamePlusOpenParen ~ `");`;
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
                    mixin("alias symbol = this." ~ member ~ ";");

                    enum udaInclude = udaIndex!(ToString.Include, __traits(getAttributes, symbol)) != -1;
                    enum udaExclude = udaIndex!(ToString.Exclude, __traits(getAttributes, symbol)) != -1;
                    enum udaLabeled = udaIndex!(ToString.Labeled, __traits(getAttributes, symbol)) != -1;
                    enum udaUnlabeled = udaIndex!(ToString.Unlabeled, __traits(getAttributes, symbol)) != -1;
                    enum udaOptional = udaIndex!(ToString.Optional, __traits(getAttributes, symbol)) != -1;
                    enum udaToStringHandler = udaIndex!(ToStringHandler, __traits(getAttributes, symbol)) != -1;

                    // see std.traits.isFunction!()
                    static if (is(symbol == function) || is(typeof(symbol) == function)
                        || is(typeof(&symbol) U : U*) && is(U == function))
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

                        if (isMemberUnlabeledByDefault!(Unqual!(typeof(symbol)))(memberName))
                        {
                            labeled = false;
                        }

                        static if (udaLabeled)
                        {
                            labeled = true;
                        }

                        string membervalue = `this.` ~ member;

                        static if (udaToStringHandler)
                        {
                            alias Handlers = getUDAs!(symbol, ToStringHandler);

                            static assert(Handlers.length == 1);

                            static if (__traits(compiles, Handlers[0].Handler(typeof(symbol).init)))
                            {
                                membervalue = `getUDAs!(this.` ~ member ~ `, ToStringHandler)[0].Handler(`
                                    ~ membervalue
                                    ~ `)`;
                            }
                            else
                            {
                                return `static assert(false, "cannot determine how to call ToStringHandler");`;
                            }
                        }

                        string writestmt;

                        if (labeled)
                        {
                            writestmt = format!`sink.sinkWrite(comma, "%s=%%s", %s);`
                                (memberName, membervalue);
                        }
                        else
                        {
                            writestmt = format!`sink.sinkWrite(comma, "%%s", %s);`(membervalue);
                        }

                        static if (udaOptional)
                        {
                            import std.array : empty;

                            static if (__traits(compiles, typeof(symbol).init.empty))
                            {
                                result ~= format!`import std.array : empty; if (!%s.empty) { %s }`
                                    (membervalue, writestmt);
                            }
                            else static if (__traits(compiles, typeof(symbol).init !is null))
                            {
                                result ~= format!`if (%s !is null) { %s }`
                                    (membervalue, writestmt);
                            }
                            else static if (__traits(compiles, typeof(symbol).init != 0))
                            {
                                result ~= format!`if (%s != 0) { %s }`
                                    (membervalue, writestmt);
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
                            result ~= writestmt;
                        }
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
            static if (is(typeof(uda) == ToString))
            {
                switch (uda)
                {
                    case ToString.Include: include = true; break;
                    case ToString.Exclude: exclude = true; break;
                    case ToString.Optional: optional = true; break;
                    case ToString.Labeled: labeled = true; break;
                    case ToString.Unlabeled: unlabeled = true; break;
                    default: break;
                }
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

enum ToString
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
    Optional,
}

public bool isMemberUnlabeledByDefault(Type)(string field)
{
    import std.string : toLower;
    import std.range.primitives : ElementType, isInputRange;

    static if (isInputRange!Type)
    {
        alias BaseType = ElementType!Type;

        if (field.toLower == BaseType.stringof.toLower.pluralize)
        {
            return true;
        }
    }

    return field.toLower == Type.stringof.toLower
        || field.toLower == "time" && Type.stringof == "SysTime"
        || field.toLower == "id" && is(typeof(Type.toString));
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
