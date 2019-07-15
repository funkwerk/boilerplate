module boilerplate.builder;

import std.typecons : Nullable, Tuple;

private alias Info = Tuple!(string, "typeField", string, "builderField");

public alias Builder(T) = typeof(T.Builder());

public mixin template BuilderImpl(T, Info = Info, alias BuilderProxy = BuilderProxy, alias _toInfo = _toInfo)
{
    import boilerplate.util : formatNamed, Optional, optionallyRemoveTrailingUnderline, removeTrailingUnderline;
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
    private enum fieldInfoList = std.range.array(
        std.algorithm.map!_toInfo(
            std.range.zip(T.ConstructorInfo.fields, builderFields)));

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
        static if (__traits(hasMember, BaseType, "Builder")
            && is(typeof(BaseType.Builder().builderValue): BaseType))
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

    static foreach (info; fieldInfoList)
    {
        mixin(formatNamed!q{public BuilderFieldInfo!(info.typeField).Type %(builderField);}.values(info));
    }

    public bool isValid() const
    {
        return this.getError().isNull;
    }

    public std.typecons.Nullable!string getError() const
    {
        alias Nullable = std.typecons.Nullable;

        static foreach (info; fieldInfoList)
        {
            mixin(formatNamed!q{
                static if (BuilderFieldInfo!(info.typeField).isBuildable)
                {
                    // if the proxy has never been used as a builder,
                    // ie. either a value was assigned or it was untouched
                    // then a default value may be used instead.
                    if (this.%(builderField)._isUnset)
                    {
                        static if (!T.ConstructorInfo.FieldInfo.%(typeField).useDefault)
                        {
                            return Nullable!string(
                                "required field '%(builderField)' not set in builder of " ~ T.stringof);
                        }
                    }
                    else if (this.%(builderField)._isBuilder)
                    {
                        auto subError = this.%(builderField)._builder.getError;

                        if (!subError.isNull)
                        {
                            return Nullable!string(subError.get ~ " of " ~ T.stringof);
                        }
                    }
                    // else it carries a full value.
                }
                else
                {
                    static if (!T.ConstructorInfo.FieldInfo.%(typeField).useDefault)
                    {
                        if (this.%(builderField).isNull)
                        {
                            return Nullable!string(
                                "required field '%(builderField)' not set in builder of " ~ T.stringof);
                        }
                    }
                }
            }.values(info));
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
        auto getArg(Info info)()
        {
            mixin(formatNamed!q{
                static if (BuilderFieldInfo!(info.typeField).isBuildable)
                {
                    if (this.%(builderField)._isBuilder)
                    {
                        return this.%(builderField)._builderValue;
                    }
                    else if (this.%(builderField)._isValue)
                    {
                        return this.%(builderField)._value;
                    }
                    else
                    {
                        assert(this.%(builderField)._isUnset);

                        static if (T.ConstructorInfo.FieldInfo.%(typeField).useDefault)
                        {
                            return T.ConstructorInfo.FieldInfo.%(typeField).fieldDefault;
                        }
                        else
                        {
                            assert(false, "isValid/build do not match 1");
                        }
                    }
                }
                else
                {
                    if (!this.%(builderField).isNull)
                    {
                        return this.%(builderField)._get;
                    }
                    else
                    {
                        static if (T.ConstructorInfo.FieldInfo.%(typeField).useDefault)
                        {
                            return T.ConstructorInfo.FieldInfo.%(typeField).fieldDefault;
                        }
                        else
                        {
                            assert(false, "isValid/build do not match 2");
                        }
                    }
                }
            }.values(info));
        }

        enum getArgArray = std.range.array(
            std.algorithm.map!(i => std.format.format!`getArg!(fieldInfoList[%s])`(i))(
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
        mixin(`alias ` ~ aliasMember ~ ` this;`);
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
        InnerType value;

        Builder!InnerType builder;

        this(inout(InnerType) value) inout pure
        {
            this.value = value;
        }

        this(inout(Builder!InnerType) builder) inout pure
        {
            this.builder = builder;
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
    in
    {
        assert(
            this.mode != Mode.builder,
            "Builder: cannot set field by value since a subfield has already been set.");
    }
    do
    {
        import boilerplate.util : move, moveEmplace;

        static if (isNullable)
        {
            if (value.isNull)
            {
                this.mode = Mode.unset;
                return;
            }

            DataWrapper newWrapper = DataWrapper(Data(value.get));
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

    public inout(T) _value() inout
    in
    {
        assert(this.mode == Mode.value);
    }
    do
    {
        static if (isNullable)
        {
            return inout(T)(this.wrapper.data.value);
        }
        else
        {
            return this.wrapper.data.value;
        }
    }

    public ref auto _builder() inout
    in
    {
        assert(this.mode == Mode.builder);
    }
    do
    {
        return this.wrapper.data.builder;
    }

    public auto _builderValue()
    in
    {
        assert(this.mode == Mode.builder);
    }
    do
    {
        static if (isNullable)
        {
            return T(this.wrapper.data.builder.builderValue);
        }
        else
        {
            return this.wrapper.data.builder.builderValue;
        }
    }

    alias _implicitBuilder this;

    public @property ref Builder!InnerType _implicitBuilder()
    {
        import boilerplate.util : move, moveEmplace;

        if (this.mode == Mode.unset)
        {
            auto newWrapper = DataWrapper(Data(Builder!InnerType.init));

            this.mode = Mode.builder;
            moveEmplace(newWrapper, this.wrapper);
        }
        else if (this.mode == Mode.value)
        {
            static if (__traits(compiles, value.BuilderFrom()))
            {
                auto value = this.wrapper.data.value;
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
}

public Info _toInfo(Tuple!(string, string) pair)
{
    return Info(pair[0], pair[1]);
}
