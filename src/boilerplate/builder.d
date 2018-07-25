module boilerplate.builder;

import boilerplate.util;
import std.algorithm : map;
import std.format : format;
import std.range : array, iota, zip;
import std.traits : Unqual;
import std.typecons : Nullable, Tuple;

public struct Builder(T)
{
    static assert(__traits(hasMember, T, "ConstructorInfo"));

    private alias Info = Tuple!(string, "typeField", string, "builderField");
    private enum fields = T.ConstructorInfo.fields;
    private enum fieldInfoList = fields
        .zip(fields.map!removeTrailingUnderline)
        .map!((Tuple!(string, string) pair) => Info(pair[0], pair[1]))
        .array;

    private template BuilderFieldInfo(string member)
    {
        mixin(format!q{alias BaseType = T.ConstructorInfo.FieldInfo.%s.Type;}(member));

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

    static foreach (info; fieldInfoList)
    {
        mixin(formatNamed!q{public BuilderFieldInfo!(info.typeField).Type %(builderField);}.values(info));
    }

    public bool isValid() const
    {
        return this.getError().isNull;
    }

    public Nullable!string getError() const
    {
        static foreach (info; fieldInfoList)
        {
            mixin(formatNamed!q{
                static if (BuilderFieldInfo!(info.typeField).isBuildable)
                {
                    // if the proxy has never been used as a builder,
                    // ie. either a value was assigned or it was untouched
                    // then a default value may be used instead.
                    if (this.%(builderField).isUnset && T.ConstructorInfo.FieldInfo.%(typeField).useDefault)
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

    public @property T value(size_t line = __LINE__, string file = __FILE__)
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
                        return this.%(builderField).get;
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

        enum getArgArray = fieldInfoList.length.iota.map!(i => format!`getArg!(fieldInfoList[%s])`(i)).array;

        static if (is(T == class))
        {
            return mixin(format!q{new T(%-(%s, %))}(getArgArray));
        }
        else
        {
            return mixin(format!q{T(%-(%s, %))}(getArgArray));
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

    package bool isUnset() const
    {
        return this.mode == Mode.unset;
    }

    package bool isValue() const
    {
        return this.mode == Mode.value;
    }

    package bool isBuilder() const
    {
        return this.mode == Mode.builder;
    }

    package inout(T) value_() inout
    in
    {
        assert(this.mode == Mode.value);
    }
    do
    {
        return this.data.value;
    }

    package ref auto builder_() inout
    in
    {
        assert(this.mode == Mode.builder);
    }
    do
    {
        return this.data.builder;
    }

    alias implicitBuilder_ this;

    public @property ref Builder!T implicitBuilder_()
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
