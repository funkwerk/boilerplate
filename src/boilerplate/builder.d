module boilerplate.builder;

import std.typecons : Nullable, Tuple;

private alias Info = Tuple!(string, "typeField", string, "builderField");

public alias Builder(T) = typeof(T.Builder());

public mixin template BuilderImpl(T, Info = Info, alias BuilderProxy = BuilderProxy, alias _toInfo = _toInfo)
{
    import boilerplate.util : Optional, optionallyRemoveTrailingUnderline, removeTrailingUnderline;
    static import std.algorithm;
    static import std.format;
    static import std.meta;
    static import std.range;
    static import std.typecons;

    static assert(__traits(hasMember, T, "ConstructorInfo"));

    static if (T.ConstructorInfo.fields.length > 0)
    {
        private enum string[] builderFields = [
            std.meta.staticMap!(optionallyRemoveTrailingUnderline,
                std.meta.aliasSeqOf!(T.ConstructorInfo.fields))];
    }
    else
    {
        private enum string[] builderFields = [];
    }
    private enum fieldInfoList = std.range.zip(T.ConstructorInfo.fields, builderFields);

    private template BuilderFieldInfo(string member)
    {
        mixin(std.format.format!q{alias FieldType = T.ConstructorInfo.FieldInfo.%s.Type;}(member));

        import std.typecons : Nullable;

        static if (is(FieldType : Nullable!Arg, Arg))
        {
            alias BaseType = Arg;
        }
        else
        {
            alias BaseType = FieldType;
        }

        // type has a builder ... that constructs it
        // protects from such IDIOTIC DESIGN ERRORS as `alias Nullable!T.get this`
        // NOTE: can't use hasMember because https://issues.dlang.org/show_bug.cgi?id=13269
        static if (__traits(compiles, BaseType.Builder()))
        {
            alias BuilderResultType = typeof(BaseType.Builder().builderValue);

            static if (is(BuilderResultType: BaseType))
            {
                alias Type = BuilderProxy!FieldType;
                enum isBuildable = true;
            }
            else
            {
                alias Type = Optional!FieldType;
                enum isBuildable = false;
            }
        }
        else static if (is(FieldType == E[], E))
        {
            static if (__traits(compiles, E.Builder()))
            {
                alias Type = BuilderProxy!FieldType;
                enum isBuildable = true;
            }
            else
            {
                alias Type = Optional!FieldType;
                enum isBuildable = false;
            }
        }
        else
        {
            alias Type = Optional!FieldType;
            enum isBuildable = false;
        }
    }

    static foreach (typeField, builderField; fieldInfoList)
    {
        mixin(`public BuilderFieldInfo!typeField.Type ` ~ builderField ~ `;`);
    }

    public bool isValid() const
    {
        return this.getError().isNull;
    }

    public std.typecons.Nullable!string getError() const
    {
        alias Nullable = std.typecons.Nullable;

        static foreach (typeField, builderField; fieldInfoList)
        {
            static if (BuilderFieldInfo!(typeField).isBuildable)
            {
                // if the proxy has never been used as a builder,
                // ie. either a value was assigned or it was untouched
                // then a default value may be used instead.
                if (__traits(getMember, this, builderField)._isUnset)
                {
                    static if (!__traits(getMember, T.ConstructorInfo.FieldInfo, typeField).useDefault)
                    {
                        return Nullable!string(
                            "required field '" ~ builderField ~ "' not set in builder of " ~ T.stringof);
                    }
                }
                else if (__traits(getMember, this, builderField)._isBuilder)
                {
                    auto subError = __traits(getMember, this, builderField)._builder.getError;

                    if (!subError.isNull)
                    {
                        return Nullable!string(subError.get ~ " of " ~ T.stringof);
                    }
                }
                // else it carries a full value.
            }
            else
            {
                static if (!__traits(getMember, T.ConstructorInfo.FieldInfo, typeField).useDefault)
                {
                    if (__traits(getMember, this, builderField).isNull)
                    {
                        return Nullable!string(
                            "required field '" ~ builderField ~ "' not set in builder of " ~ T.stringof);
                    }
                }
            }
        }
        return Nullable!string();
    }

    public @property T builderValue(size_t line = __LINE__, string file = __FILE__)
    in
    {
        import core.exception : AssertError;

        if (!this.isValid)
        {
            throw new AssertError(this.getError.get, file, line);
        }
    }
    do
    {
        auto getArg(string typeField, string builderField)()
        {
            static if (BuilderFieldInfo!(typeField).isBuildable)
            {
                import std.meta : Alias;

                alias Type = Alias!(__traits(getMember, T.ConstructorInfo.FieldInfo, typeField)).Type;

                static if (is(Type == E[], E))
                {
                    if (__traits(getMember, this, builderField)._isArray)
                    {
                        return __traits(getMember, this, builderField)._arrayValue;
                    }
                    else if (__traits(getMember, this, builderField)._isValue)
                    {
                        return __traits(getMember, this, builderField)._value;
                    }
                }
                else
                {
                    if (__traits(getMember, this, builderField)._isBuilder)
                    {
                        return __traits(getMember, this, builderField)._builderValue;
                    }
                    else if (__traits(getMember, this, builderField)._isValue)
                    {
                        return __traits(getMember, this, builderField)._value;
                    }
                }
                assert(__traits(getMember, this, builderField)._isUnset);

                static if (__traits(getMember, T.ConstructorInfo.FieldInfo, typeField).useDefault)
                {
                    return __traits(getMember, T.ConstructorInfo.FieldInfo, typeField).fieldDefault;
                }
                else
                {
                    assert(false, "isValid/build do not match 1");
                }
            }
            else
            {
                if (!__traits(getMember, this, builderField).isNull)
                {
                    return __traits(getMember, this, builderField)._get;
                }
                else
                {
                    static if (__traits(getMember, T.ConstructorInfo.FieldInfo, typeField).useDefault)
                    {
                        return __traits(getMember, T.ConstructorInfo.FieldInfo, typeField).fieldDefault;
                    }
                    else
                    {
                        assert(false, "isValid/build do not match 2");
                    }
                }
            }
        }

        enum getArgArray = std.range.array(
            std.algorithm.map!(i => std.format.format!`getArg!(fieldInfoList[%s][0], fieldInfoList[%s][1])`(i, i))(
                std.range.iota(fieldInfoList.length)));

        static if (is(T == class))
        {
            return mixin(std.format.format!q{new T(%-(%s, %))}(getArgArray));
        }
        else
        {
            return mixin(std.format.format!q{T(%-(%s, %))}(getArgArray));
        }
    }

    static foreach (aliasMember; __traits(getAliasThis, T))
    {
        mixin(`alias ` ~ optionallyRemoveTrailingUnderline!aliasMember ~ ` this;`);
    }

    static if (!std.algorithm.canFind(
        std.algorithm.map!removeTrailingUnderline(T.ConstructorInfo.fields),
        "value"))
    {
        public alias value = builderValue;
    }
}

// value that is either a T, or a Builder for T.
// Used for nested builder initialization.
public struct BuilderProxy(T)
{
    private enum Mode
    {
        unset,
        builder,
        value,
        array, // array of builders
    }

    static if (is(T : Nullable!Arg, Arg))
    {
        enum isNullable = true;
        alias InnerType = Arg;
    }
    else
    {
        enum isNullable = false;
        alias InnerType = T;
    }

    private union Data
    {
        T value;

        this(inout(T) value) inout pure
        {
            this.value = value;
        }

        static if (is(T == E[], E))
        {
            E.BuilderType!()[] array;

            this(inout(E.BuilderType!())[] array) inout pure
            {
                this.array = array;
            }
        }
        else
        {
            InnerType.BuilderType!() builder;

            this(inout(InnerType.BuilderType!()) builder) inout pure
            {
                this.builder = builder;
            }
        }
    }

    struct DataWrapper
    {
        Data data;
    }

    private Mode mode = Mode.unset;

    private DataWrapper wrapper = DataWrapper.init;

    public this(T value)
    {
        opAssign(value);
    }

    public void opAssign(T value)
    in(this.mode != Mode.builder,
        "Builder: cannot set field by value since a subfield has already been set.")
    {
        import boilerplate.util : move, moveEmplace;

        static if (isNullable)
        {
            DataWrapper newWrapper = DataWrapper(Data(value));
        }
        else
        {
            DataWrapper newWrapper = DataWrapper(Data(value));
        }

        if (this.mode == Mode.value)
        {
            move(newWrapper, this.wrapper);
        }
        else
        {
            moveEmplace(newWrapper, this.wrapper);
        }
        this.mode = Mode.value;
    }

    static if (isNullable)
    {
        public void opAssign(InnerType value)
        {
            return opAssign(T(value));
        }
    }

    public bool _isUnset() const
    {
        return this.mode == Mode.unset;
    }

    public bool _isValue() const
    {
        return this.mode == Mode.value;
    }

    public bool _isBuilder() const
    {
        return this.mode == Mode.builder;
    }

    public bool _isArray() const
    {
        return this.mode == Mode.array;
    }

    public inout(T) _value() inout
    in (this.mode == Mode.value)
    {
        return this.wrapper.data.value;
    }

    public ref auto _builder() inout
    in (this.mode == Mode.builder)
    {
        static if (is(T == E[], E))
        {
            int i = 0;

            assert(i != 0); // assert(false) but return stays "reachable"
            return E.Builder();
        }
        else
        {
            return this.wrapper.data.builder;
        }
    }

    public auto _builderValue()
    in (this.mode == Mode.builder)
    {
        static if (is(T == E[], E))
        {
            int i = 0;

            assert(i != 0); // assert(false) but return stays "reachable"
            return E.Builder();
        }
        else static if (isNullable)
        {
            return T(this.wrapper.data.builder.builderValue);
        }
        else
        {
            return this.wrapper.data.builder.builderValue;
        }
    }

    public T _arrayValue()
    in (this.mode == Mode.array)
    {
        import std.algorithm : map;
        import std.array : array;

        static if (is(T == E[], E))
        {
            // enforce that E is the return value
            static E builderValue(Element)(Element element) { return element.builderValue; }

            return this.wrapper.data.array.map!builderValue.array;
        }
        else
        {
            assert(false);
        }
    }

    static if (is(T == E[], E))
    {
        public ref E.BuilderType!() opIndex(size_t index) return
        in (this.mode == Mode.unset || this.mode == Mode.array,
            "cannot build array for already initialized field")
        {
            import boilerplate.util : moveEmplace;

            if (this.mode == Mode.unset)
            {
                auto newWrapper = DataWrapper(Data(new E.BuilderType!()[](index + 1)));

                this.mode = Mode.array;
                moveEmplace(newWrapper, this.wrapper);
            }
            else while (this.wrapper.data.array.length <= index)
            {
                this.wrapper.data.array ~= E.Builder();
            }
            return this.wrapper.data.array[index];
        }

        public void opOpAssign(string op, R)(R rhs)
        if (op == "~")
        in (this.mode == Mode.unset || this.mode == Mode.value,
            "Builder cannot append to array already initialized by index")
        {
            if (this.mode == Mode.unset)
            {
                opAssign(null);
            }
            opAssign(this.wrapper.data.value ~ rhs);
        }
    }
    else
    {
        public @property ref InnerType.BuilderType!() _implicitBuilder()
        {
            import boilerplate.util : move, moveEmplace;

            if (this.mode == Mode.unset)
            {
                auto newWrapper = DataWrapper(Data(InnerType.BuilderType!().init));

                this.mode = Mode.builder;
                moveEmplace(newWrapper, this.wrapper);
            }
            else if (this.mode == Mode.value)
            {
                static if (isNullable)
                {
                    assert(
                        !this.wrapper.data.value.isNull,
                        "Builder: cannot set sub-field directly since field was explicitly " ~
                        "initialized to Nullable.null");
                    auto value = this.wrapper.data.value.get;
                }
                else
                {
                    auto value = this.wrapper.data.value;
                }
                static if (__traits(compiles, value.BuilderFrom()))
                {
                    auto newWrapper = DataWrapper(Data(value.BuilderFrom()));

                    this.mode = Mode.builder;
                    move(newWrapper, this.wrapper);
                }
                else
                {
                    assert(
                        false,
                        "Builder: cannot set sub-field directly since field is already being initialized by value " ~
                        "(and BuilderFrom is unavailable in " ~ typeof(this.wrapper.data.value).stringof ~ ")");
                }
            }

            return this.wrapper.data.builder;
        }

        alias _implicitBuilder this;
    }
}

public Info _toInfo(Tuple!(string, string) pair)
{
    return Info(pair[0], pair[1]);
}
