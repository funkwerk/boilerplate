module config.string;

import std.datetime : Date, DateTimeException, Duration, SysTime, TimeOfDay, UTC;
import std.format : formattedWrite;
import std.traits : Unqual;

/**
 * Customize this in your own project!
 */

void toString(Date date, scope void delegate(const(char)[]) sink)
{
    sink(date.toISOExtString);
}

void toString(SysTime sysTime, scope void delegate(const(char)[]) sink)
{
    if (sysTime == SysTime.init && sysTime.timezone is null)
    {
        throw new DateTimeException("time undefined");
    }

    sysTime.fracSecs = Duration.zero;
    sink(sysTime.toISOExtString);
}

void toString(TimeOfDay timeOfDay, scope void delegate(const(char)[]) sink)
{
    sink(timeOfDay.toISOExtString);
}

/**
 * Format `Duration` as ISO 8601 duration.
 */
void toString(Duration duration, scope void delegate(const(char)[]) sink)
{
    if (duration < Duration.zero)
    {
        sink("-");
        duration = -duration;
    }

    auto result = duration.split!("days", "hours", "minutes", "seconds", "msecs");

    with (result)
    {
        sink("P");

        if (days != 0)
        {
            sink.formattedWrite("%sD", days);
        }

        const bool allTimesNull = hours == 0 && minutes == 0 && seconds == 0 && msecs == 0;
        const bool allNull = allTimesNull && days == 0;

        if (!allTimesNull || allNull)
        {
            sink("T");
            if (hours != 0)
            {
                sink.formattedWrite("%sH", hours);
            }
            if (minutes != 0)
            {
                sink.formattedWrite("%sM", minutes);
            }
            if (seconds != 0 || msecs != 0 || allNull)
            {
                sink.formattedWrite("%s", seconds);
                sink.writeMillis(msecs);
                sink("S");
            }
        }
    }
}

unittest
{
    import std.datetime : DateTime, DateTimeException, msecs;
    import unit_threaded.should : shouldThrow;

    DateTime dateTime = DateTime.fromISOExtString("2003-02-01T11:55:00");

    SysTime(dateTime).sinkShouldEqual("2003-02-01T11:55:00");
    SysTime(dateTime, UTC()).sinkShouldEqual("2003-02-01T11:55:00Z");
    SysTime(dateTime, 123.msecs).sinkShouldEqual("2003-02-01T11:55:00");

    DateTime epoch = DateTime.fromISOExtString("0001-01-01T00:00:00");

    SysTime(epoch).sinkShouldEqual("0001-01-01T00:00:00");
    SysTime(epoch, UTC()).sinkShouldEqual("0001-01-01T00:00:00Z");

    alias nullSink = (const(char)[]) { };

    toString(SysTime(), nullSink).shouldThrow!DateTimeException;
}

unittest
{
    Date(2003, 2, 1).sinkShouldEqual("2003-02-01");
}

unittest
{
    TimeOfDay(1, 2, 3).sinkShouldEqual("01:02:03");
}

unittest
{
    import std.datetime : days, hours, minutes, seconds, msecs;

    (1.days + 2.hours + 3.minutes + 4.seconds + 500.msecs).sinkShouldEqual("P1DT2H3M4.5S");
    (1.days).sinkShouldEqual("P1D");
    (Duration.zero).sinkShouldEqual("PT0S");
    (1.msecs).sinkShouldEqual("PT0.001S");
    (-(1.hours + 2.minutes + 3.seconds + 450.msecs)).sinkShouldEqual("-PT1H2M3.45S");
}

/**
 * Converts the specified milliseconds value into a representation with as few digits as possible.
 */
private void writeMillis(scope void delegate(const(char)[]) sink, long millis)
in
{
    assert(0 <= millis && millis < 1000);
}
body
{
    if (millis == 0)
    {
        sink("");
    }
    else if (millis % 100 == 0)
    {
        sink.formattedWrite(".%01d", millis / 100);
    }
    else if (millis % 10 == 0)
    {
        sink.formattedWrite(".%02d", millis / 10);
    }
    else
    {
        sink.formattedWrite(".%03d", millis);
    }
}

private void sinkShouldEqual(T)(T arg, string comparison, in string file = __FILE__, in size_t line = __LINE__)
{
    import std.conv : to;
    import unit_threaded.should : shouldEqual;

    struct SinkType
    {
        void toString(scope void delegate(const(char)[]) sink)
        {
            .toString(arg, sink);
        }
    }

    SinkType().to!string.shouldEqual(comparison, file, line);
}
