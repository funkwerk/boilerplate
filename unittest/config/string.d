module config.string;

import std.datetime;

void toString(SysTime time, scope void delegate(const(char)[]) sink)
{
    sink(time.toISOExtString);
}

@("can format SysTime")
unittest
{
    import unit_threaded.should : shouldEqual;

    string generatedString;

    scope void delegate(const(char)[]) sink = (const(char)[] fragment) {
        generatedString ~= fragment;
    };

    const SysTime time = SysTime.fromISOExtString("2003-02-01T11:55:00Z");
    toString(time, sink);

    generatedString.shouldEqual("2003-02-01T11:55:00Z");
}
