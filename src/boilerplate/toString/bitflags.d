module boilerplate.toString.bitflags;

import std.typecons : BitFlags;

void toString(T: const BitFlags!Enum, Enum)(const T field, scope void delegate(const(char)[]) sink)
{
    import std.conv : to;
    import std.traits : EnumMembers;

    bool firstMember = true;

    sink(Enum.stringof);
    sink("(");

    static foreach (member; EnumMembers!Enum)
    {
        if (field & member)
        {
            if (firstMember)
            {
                firstMember = false;
            }
            else
            {
                sink(", ");
            }

            enum name = to!string(member);

            sink(name);
        }
    }
    sink(")");
}

@("can format bitflags")
unittest
{
    import unit_threaded.should : shouldEqual;

    string generatedString;

    scope sink = (const(char)[] fragment) {
        generatedString ~= fragment;
    };

    enum Enum
    {
        A = 1,
        B = 2,
    }

    const BitFlags!Enum flags = BitFlags!Enum(Enum.A, Enum.B);

    toString(flags, sink);

    generatedString.shouldEqual("Enum(A, B)");
}
