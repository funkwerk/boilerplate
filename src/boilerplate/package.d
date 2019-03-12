module boilerplate;

public import boilerplate.accessors;

public import boilerplate.autostring;

public import boilerplate.conditions;

public import boilerplate.constructor;

enum GenerateAll = GenerateThis ~ GenerateToString ~ GenerateFieldAccessors ~ GenerateInvariants;

@("can use all four generators at once")
unittest
{
    import core.exception : AssertError;
    import std.conv : to;
    import unit_threaded.should : shouldEqual, shouldThrow;

    class Class
    {
        @ConstRead @Write @NonInit
        int i_;

        mixin(GenerateAll);
    }

    auto obj = new Class(5);

    obj.i.shouldEqual(5);
    obj.to!string.shouldEqual("Class(i=5)");
    obj.i(0).shouldThrow!AssertError;
}

// regression test for workaround for https://issues.dlang.org/show_bug.cgi?id=19731
@("accessor on field in struct with invariant and constructor")
unittest
{
    import core.exception : AssertError;
    import unit_threaded.should : shouldThrow;

    struct Struct
    {
        @NonNull
        @ConstRead
        Object constObject_;

        @NonNull
        @Read
        Object object_;

        mixin(GenerateAll);
    }

    Struct().constObject.shouldThrow!AssertError;
    Struct().object.shouldThrow!AssertError;
}
