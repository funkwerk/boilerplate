module boilerplate;

public import boilerplate.accessors;

public import boilerplate.autostring;

public import boilerplate.constructor;

public import boilerplate.conditions;

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
