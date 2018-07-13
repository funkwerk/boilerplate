module boilerplate.builder;

public struct Builder(T)
{
    import boilerplate.util : Optional, formatNamed, removeTrailingUnderline;
    import std.algorithm : map;
    import std.range : array;
    import std.typecons : Nullable, Tuple;

    static assert(__traits(hasMember, T, "ConstructorInfo"));

    private enum builderFields = T.ConstructorInfo.fields.map!removeTrailingUnderline.array;

    private alias Info = Tuple!(string, "builderField");

    private template BuilderFieldInfo(int i)
    {
        alias BaseType = T.ConstructorInfo.Types[i];

        // type has a builder ... that constructs it
        // protects from such IDIOTIC DESIGN ERRORS as `alias Nullable!T.get this`
        static if (__traits(hasMember, BaseType, "Builder")
            && is(typeof(BaseType.Builder().value) == BaseType))
        {
            alias Type = BuilderProxy!BaseType;
            enum isBuildable = true;
        }
        else
        {
            alias Type = Optional!BaseType;
            enum isBuildable = false;
        }
    }

    static foreach (i, builderField; builderFields)
    {
        mixin(formatNamed!q{public BuilderFieldInfo!i.Type %(builderField);}.values(Info(builderField)));
    }

    public bool isValid() const
    {
        return getError().isNull;
    }

    public Nullable!string getError() const
    {
        static foreach (i, builderField; builderFields)
        {
            mixin(formatNamed!q{
                static if (BuilderFieldInfo!i.isBuildable)
                {
                    // if the proxy has never been used as a builder,
                    // ie. either a value was assigned or it was untouched
                    // then a default value may be used instead.
                    if (this.%(builderField).isUnset && T.ConstructorInfo.useDefaults[i])
                    {
                    }
                    else
                    {
                        if (this.%(builderField).isBuilder)
                        {
                            auto subError = this.%(builderField).builder_.getError;

                            if (!subError.isNull)
                            {
                                return Nullable!string(subError.get ~ " of " ~ T.stringof);
                            }
                        }
                    }
                }
                else
                {
                    static if (!T.ConstructorInfo.useDefaults[i])
                    {
                        if (this.%(builderField).isNull)
                        {
                            return Nullable!string(
                                "required field '%(builderField)' not set in builder of " ~ T.stringof);
                        }
                    }
                }
            }.values(Info(builderField)));
        }
        return Nullable!string();
    }

    public @property T value(size_t line = __LINE__, string file = __FILE__) const
    in
    {
        import core.exception : AssertError;

        if (!isValid)
        {
            throw new AssertError(getError.get, file, line);
        }
    }
    do
    {
        import std.algorithm : map;
        import std.format : format;
        import std.range : array, iota;
        import std.traits : Unqual;

        auto getArg(int i)()
        {
            enum builderField = builderFields[i];

            mixin(formatNamed!q{
                static if (BuilderFieldInfo!i.isBuildable)
                {
                    if (this.%(builderField).isBuilder)
                    {
                        return this.%(builderField).builder_.value;
                    }
                    else if (this.%(builderField).isValue)
                    {
                        return this.%(builderField).value_;
                    }
                    else
                    {
                        assert(this.%(builderField).isUnset);

                        static if (T.ConstructorInfo.useDefaults[i])
                        {
                            return T.ConstructorInfo.defaults[i];
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
                        return this.%(builderField).get;
                    }
                    else
                    {
                        static if (T.ConstructorInfo.useDefaults[i])
                        {
                            return T.ConstructorInfo.defaults[i];
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
            return mixin(format!q{new T(%-(%s, %))}(
                builderFields.length.iota.map!(i => format!`getArg!%s`(i)).array));
        }
        else
        {
            return mixin(format!q{T(%-(%s, %))}(
                builderFields.length.iota.map!(i => format!`getArg!%s`(i)).array));
        }
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

    private union Data
    {
        Builder!T builder;
        T value;
    }

    private Mode mode = Mode.unset;

    private Data data;

    public void opAssign(T value)
    in
    {
        assert(
            this.mode != Mode.builder,
            "Builder: cannot set sub-field by value since a subfield has already been set.");
    }
    do
    {
        this.mode = Mode.value;
        this.data.value = value;
    }

    package bool isUnset() const @nogc nothrow pure @safe
    {
        return this.mode == Mode.unset;
    }

    package bool isValue() const @nogc nothrow pure @safe
    {
        return this.mode == Mode.value;
    }

    package bool isBuilder() const @nogc nothrow pure @safe
    {
        return this.mode == Mode.builder;
    }

    package T value_() const @nogc nothrow pure @safe
    in
    {
        assert(this.mode == Mode.value);
    }
    do
    {
        return this.data.value;
    }

    package ref auto builder_() const @nogc nothrow pure @safe
    in
    {
        assert(this.mode == Mode.builder);
    }
    do
    {
        return this.data.builder;
    }

    alias builder_implicit_ this;

    public @property ref Builder!T builder_implicit_() @nogc nothrow pure @safe
    in
    {
        assert(
            this.mode != Mode.value,
            "Builder: cannot set sub-field directly since field is already being initialized by value");
    }
    do
    {
        if (this.mode == Mode.unset)
        {
            this.mode = Mode.builder;
            this.data.builder = Builder!T.init;
        }

        return this.data.builder;
    }
}
