const std = @import("std");
const c = @cImport({
    @cInclude("libpq-fe.h");
});

const usage =
    \\\\Usage:
    \\\\  cohort-momentum-ledger init-db
    \\\\  cohort-momentum-ledger seed-db
    \\\\  cohort-momentum-ledger add --cohort NAME --week N --attendance N --submissions N --sessions N [--notes TEXT]
    \\\\  cohort-momentum-ledger list [--cohort NAME]
    \\\\  cohort-momentum-ledger summary [--cohort NAME]
    \\\\  cohort-momentum-ledger trend --cohort NAME [--weeks N]
    \\\\  cohort-momentum-ledger export [--cohort NAME] --out PATH
    \\\\
    \\\\Environment:
    \\\\  GS_DATABASE_URL   Postgres connection string for the target database.
    \\\\
;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var arena = std.heap.ArenaAllocator.init(gpa.allocator());
    defer arena.deinit();
    const allocator = arena.allocator();

    const args = try std.process.argsAlloc(allocator);
    if (args.len < 2) {
        try printUsage();
        return;
    }

    const command = args[1];
    var options = try parseOptions(allocator, args[2..]);
    defer options.deinit();

    if (std.mem.eql(u8, command, "init-db")) {
        try withConnection(allocator, initDb, &options);
    } else if (std.mem.eql(u8, command, "seed-db")) {
        try withConnection(allocator, seedDb, &options);
    } else if (std.mem.eql(u8, command, "add")) {
        try withConnection(allocator, struct {
            fn call(conn: *c.PGconn, alloc: std.mem.Allocator, opts: *const Options) !void {
                try addEntry(conn, alloc, opts);
            }
        }.call, &options);
    } else if (std.mem.eql(u8, command, "list")) {
        try withConnection(allocator, struct {
            fn call(conn: *c.PGconn, alloc: std.mem.Allocator, opts: *const Options) !void {
                try listEntries(conn, alloc, opts);
            }
        }.call, &options);
    } else if (std.mem.eql(u8, command, "summary")) {
        try withConnection(allocator, struct {
            fn call(conn: *c.PGconn, alloc: std.mem.Allocator, opts: *const Options) !void {
                try summaryEntries(conn, alloc, opts);
            }
        }.call, &options);
    } else if (std.mem.eql(u8, command, "trend")) {
        try withConnection(allocator, struct {
            fn call(conn: *c.PGconn, alloc: std.mem.Allocator, opts: *const Options) !void {
                try trendEntries(conn, alloc, opts);
            }
        }.call, &options);
    } else if (std.mem.eql(u8, command, "export")) {
        try withConnection(allocator, struct {
            fn call(conn: *c.PGconn, alloc: std.mem.Allocator, opts: *const Options) !void {
                try exportEntries(conn, alloc, opts);
            }
        }.call, &options);
    } else {
        try printUsage();
    }
}

fn printUsage() !void {
    const writer = std.io.getStdOut().writer();
    try writer.writeAll(usage);
}

const Options = std.StringHashMap([]const u8);

fn parseOptions(allocator: std.mem.Allocator, args: []const []const u8) !Options {
    var map = Options.init(allocator);
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (!std.mem.startsWith(u8, arg, "--")) {
            return error.InvalidArguments;
        }
        const key = arg[2..];
        if (i + 1 >= args.len) {
            return error.InvalidArguments;
        }
        const value = args[i + 1];
        try map.put(key, value);
        i += 1;
    }
    return map;
}

fn getRequiredOpt(opts: *const Options, key: []const u8) ![]const u8 {
    if (opts.get(key)) |value| {
        return value;
    }
    return error.MissingOption;
}

fn withConnection(
    allocator: std.mem.Allocator,
    func: fn (*c.PGconn, std.mem.Allocator, *const Options) anyerror!void,
    opts: *const Options,
) !void {
    const conninfo = try getDatabaseUrl(allocator);
    const conn = c.PQconnectdb(conninfo.ptr);
    if (conn == null) {
        return error.ConnectionFailed;
    }
    defer c.PQfinish(conn);

    if (c.PQstatus(conn) != c.CONNECTION_OK) {
        const msg = c.PQerrorMessage(conn);
        try std.io.getStdErr().writer().print("Database connection failed: {s}\\n", .{msg});
        return error.ConnectionFailed;
    }

    try func(conn, allocator, opts);
}

fn getDatabaseUrl(allocator: std.mem.Allocator) ![:0]u8 {
    const value = std.process.getEnvVarOwned(allocator, "GS_DATABASE_URL") catch |err| {
        if (err == error.EnvironmentVariableNotFound) {
            try std.io.getStdErr().writer().writeAll("GS_DATABASE_URL is not set.\\n");
            try printUsage();
            return error.MissingDatabaseUrl;
        }
        return err;
    };
    return std.cstr.addNullByte(allocator, value);
}

fn initDb(conn: *c.PGconn, allocator: std.mem.Allocator, opts: *const Options) !void {
    _ = opts;
    try execFile(conn, allocator, "sql/schema.sql");
    try std.io.getStdOut().writer().writeAll("Schema applied.\\n");
}

fn seedDb(conn: *c.PGconn, allocator: std.mem.Allocator, opts: *const Options) !void {
    _ = opts;
    try execFile(conn, allocator, "sql/seed.sql");
    try std.io.getStdOut().writer().writeAll("Seed data inserted.\\n");
}

fn addEntry(conn: *c.PGconn, allocator: std.mem.Allocator, opts: *const Options) !void {
    const cohort = try getRequiredOpt(opts, "cohort");
    const week = try getRequiredOpt(opts, "week");
    const attendance = try getRequiredOpt(opts, "attendance");
    const submissions = try getRequiredOpt(opts, "submissions");
    const sessions = try getRequiredOpt(opts, "sessions");
    const notes = opts.get("notes") orelse "";

    const cohort_z = try std.cstr.addNullByte(allocator, cohort);
    const week_z = try std.cstr.addNullByte(allocator, week);
    const attendance_z = try std.cstr.addNullByte(allocator, attendance);
    const submissions_z = try std.cstr.addNullByte(allocator, submissions);
    const sessions_z = try std.cstr.addNullByte(allocator, sessions);
    const notes_z = try std.cstr.addNullByte(allocator, notes);

    var values: [6][*c]const u8 = .{
        cohort_z.ptr,
        week_z.ptr,
        attendance_z.ptr,
        submissions_z.ptr,
        sessions_z.ptr,
        notes_z.ptr,
    };

    const sql =
        "INSERT INTO groupscholar_cohort_momentum.momentum_entries " ++
        "(cohort_name, week_index, attendance_count, submission_count, session_count, notes) " ++
        "VALUES ($1, $2, $3, $4, $5, $6);";

    const result = c.PQexecParams(
        conn,
        sql,
        6,
        null,
        &values,
        null,
        null,
        0,
    );
    defer c.PQclear(result);

    try ensureCommandOk(conn, result);
    try std.io.getStdOut().writer().writeAll("Entry added.\\n");
}

fn listEntries(conn: *c.PGconn, allocator: std.mem.Allocator, opts: *const Options) !void {
    const writer = std.io.getStdOut().writer();
    if (opts.get("cohort")) |cohort| {
        const cohort_z = try std.cstr.addNullByte(allocator, cohort);
        var values: [1][*c]const u8 = .{cohort_z.ptr};
        const sql =
            "SELECT cohort_name, week_index, attendance_count, submission_count, session_count, notes, recorded_at " ++
            "FROM groupscholar_cohort_momentum.momentum_entries " ++
            "WHERE cohort_name = $1 " ++
            "ORDER BY week_index DESC, recorded_at DESC;";
        const result = c.PQexecParams(conn, sql, 1, null, &values, null, null, 0);
        defer c.PQclear(result);
        try ensureTuplesOk(conn, result);
        try printRows(result, writer);
    } else {
        const sql =
            "SELECT cohort_name, week_index, attendance_count, submission_count, session_count, notes, recorded_at " ++
            "FROM groupscholar_cohort_momentum.momentum_entries " ++
            "ORDER BY cohort_name, week_index DESC, recorded_at DESC;";
        const result = c.PQexec(conn, sql);
        defer c.PQclear(result);
        try ensureTuplesOk(conn, result);
        try printRows(result, writer);
    }
}

fn summaryEntries(conn: *c.PGconn, allocator: std.mem.Allocator, opts: *const Options) !void {
    const writer = std.io.getStdOut().writer();
    if (opts.get("cohort")) |cohort| {
        const cohort_z = try std.cstr.addNullByte(allocator, cohort);
        var values: [1][*c]const u8 = .{cohort_z.ptr};
        const sql =
            "SELECT COUNT(*) AS entries, " ++
            "COALESCE(SUM(attendance_count), 0) AS attendance_total, " ++
            "COALESCE(SUM(submission_count), 0) AS submission_total, " ++
            "COALESCE(SUM(session_count), 0) AS session_total, " ++
            "ROUND(COALESCE(AVG(attendance_count), 0)::numeric, 2) AS attendance_avg, " ++
            "ROUND(COALESCE(AVG(submission_count), 0)::numeric, 2) AS submission_avg, " ++
            "ROUND(COALESCE(AVG(session_count), 0)::numeric, 2) AS session_avg " ++
            "FROM groupscholar_cohort_momentum.momentum_entries " ++
            "WHERE cohort_name = $1;";
        const result = c.PQexecParams(conn, sql, 1, null, &values, null, null, 0);
        defer c.PQclear(result);
        try ensureTuplesOk(conn, result);
        try printRows(result, writer);
    } else {
        const sql =
            "SELECT COUNT(*) AS entries, " ++
            "COALESCE(SUM(attendance_count), 0) AS attendance_total, " ++
            "COALESCE(SUM(submission_count), 0) AS submission_total, " ++
            "COALESCE(SUM(session_count), 0) AS session_total, " ++
            "ROUND(COALESCE(AVG(attendance_count), 0)::numeric, 2) AS attendance_avg, " ++
            "ROUND(COALESCE(AVG(submission_count), 0)::numeric, 2) AS submission_avg, " ++
            "ROUND(COALESCE(AVG(session_count), 0)::numeric, 2) AS session_avg " ++
            "FROM groupscholar_cohort_momentum.momentum_entries;";
        const result = c.PQexec(conn, sql);
        defer c.PQclear(result);
        try ensureTuplesOk(conn, result);
        try printRows(result, writer);
    }
}

fn trendEntries(conn: *c.PGconn, allocator: std.mem.Allocator, opts: *const Options) !void {
    const cohort = try getRequiredOpt(opts, "cohort");
    const weeks = opts.get("weeks") orelse "6";

    const cohort_z = try std.cstr.addNullByte(allocator, cohort);
    const weeks_z = try std.cstr.addNullByte(allocator, weeks);

    var values: [2][*c]const u8 = .{ cohort_z.ptr, weeks_z.ptr };
    const sql =
        "WITH ordered AS (" ++
        "  SELECT cohort_name, week_index, attendance_count, submission_count, session_count, " ++
        "    (attendance_count * 0.5 + submission_count * 0.35 + session_count * 0.15) AS momentum_score, " ++
        "    LAG(attendance_count) OVER (PARTITION BY cohort_name ORDER BY week_index) AS prev_attendance, " ++
        "    LAG(submission_count) OVER (PARTITION BY cohort_name ORDER BY week_index) AS prev_submission, " ++
        "    LAG(session_count) OVER (PARTITION BY cohort_name ORDER BY week_index) AS prev_session, " ++
        "    LAG(attendance_count * 0.5 + submission_count * 0.35 + session_count * 0.15) " ++
        "      OVER (PARTITION BY cohort_name ORDER BY week_index) AS prev_momentum " ++
        "  FROM groupscholar_cohort_momentum.momentum_entries " ++
        "  WHERE cohort_name = $1" ++
        ") " ++
        "SELECT cohort_name, week_index, attendance_count, submission_count, session_count, " ++
        "  ROUND(momentum_score::numeric, 2) AS momentum_score, " ++
        "  (attendance_count - COALESCE(prev_attendance, attendance_count)) AS attendance_delta, " ++
        "  (submission_count - COALESCE(prev_submission, submission_count)) AS submission_delta, " ++
        "  (session_count - COALESCE(prev_session, session_count)) AS session_delta, " ++
        "  ROUND((momentum_score - COALESCE(prev_momentum, momentum_score))::numeric, 2) AS momentum_delta " ++
        "FROM ordered " ++
        "ORDER BY week_index DESC " ++
        "LIMIT $2;";

    const result = c.PQexecParams(conn, sql, 2, null, &values, null, null, 0);
    defer c.PQclear(result);
    try ensureTuplesOk(conn, result);
    try printRows(result, std.io.getStdOut().writer());
}

fn exportEntries(conn: *c.PGconn, allocator: std.mem.Allocator, opts: *const Options) !void {
    const out_path = try getRequiredOpt(opts, "out");

    var file: ?std.fs.File = null;
    var writer = std.io.getStdOut().writer();
    if (!std.mem.eql(u8, out_path, "-")) {
        file = try std.fs.cwd().createFile(out_path, .{ .truncate = true });
        writer = file.?.writer();
    }
    defer if (file) |f| f.close();

    if (opts.get("cohort")) |cohort| {
        const cohort_z = try std.cstr.addNullByte(allocator, cohort);
        var values: [1][*c]const u8 = .{cohort_z.ptr};
        const sql =
            "SELECT cohort_name, week_index, attendance_count, submission_count, session_count, notes, recorded_at " ++
            "FROM groupscholar_cohort_momentum.momentum_entries " ++
            "WHERE cohort_name = $1 " ++
            "ORDER BY week_index ASC, recorded_at ASC;";
        const result = c.PQexecParams(conn, sql, 1, null, &values, null, null, 0);
        defer c.PQclear(result);
        try ensureTuplesOk(conn, result);
        try writeCsv(result, writer);
    } else {
        const sql =
            "SELECT cohort_name, week_index, attendance_count, submission_count, session_count, notes, recorded_at " ++
            "FROM groupscholar_cohort_momentum.momentum_entries " ++
            "ORDER BY cohort_name ASC, week_index ASC, recorded_at ASC;";
        const result = c.PQexec(conn, sql);
        defer c.PQclear(result);
        try ensureTuplesOk(conn, result);
        try writeCsv(result, writer);
    }
}

fn execFile(conn: *c.PGconn, allocator: std.mem.Allocator, path: []const u8) !void {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    const contents = try file.readToEndAlloc(allocator, 1024 * 1024);
    const result = c.PQexec(conn, contents.ptr);
    defer c.PQclear(result);
    try ensureCommandOk(conn, result);
}

fn ensureCommandOk(conn: *c.PGconn, result: *c.PGresult) !void {
    if (result == null) {
        return error.QueryFailed;
    }
    const status = c.PQresultStatus(result);
    if (status != c.PGRES_COMMAND_OK) {
        const msg = c.PQerrorMessage(conn);
        try std.io.getStdErr().writer().print("Query failed: {s}\\n", .{msg});
        return error.QueryFailed;
    }
}

fn ensureTuplesOk(conn: *c.PGconn, result: *c.PGresult) !void {
    if (result == null) {
        return error.QueryFailed;
    }
    const status = c.PQresultStatus(result);
    if (status != c.PGRES_TUPLES_OK) {
        const msg = c.PQerrorMessage(conn);
        try std.io.getStdErr().writer().print("Query failed: {s}\\n", .{msg});
        return error.QueryFailed;
    }
}

fn printRows(result: *c.PGresult, writer: anytype) !void {
    const rows = c.PQntuples(result);
    const cols = c.PQnfields(result);

    var row: c_int = 0;
    while (row < rows) : (row += 1) {
        var col: c_int = 0;
        while (col < cols) : (col += 1) {
            const name = c.PQfname(result, col);
            const value = c.PQgetvalue(result, row, col);
            try writer.print("{s}: {s}", .{ name, value });
            if (col + 1 < cols) {
                try writer.writeAll(" | ");
            }
        }
        try writer.writeAll("\\n");
    }
}

fn writeCsv(result: *c.PGresult, writer: anytype) !void {
    const cols = c.PQnfields(result);
    var col: c_int = 0;
    while (col < cols) : (col += 1) {
        const name = c.PQfname(result, col);
        try writeCsvValue(writer, std.mem.span(name));
        if (col + 1 < cols) {
            try writer.writeAll(",");
        }
    }
    try writer.writeAll("\\n");

    const rows = c.PQntuples(result);
    var row: c_int = 0;
    while (row < rows) : (row += 1) {
        col = 0;
        while (col < cols) : (col += 1) {
            const value = c.PQgetvalue(result, row, col);
            try writeCsvValue(writer, std.mem.span(value));
            if (col + 1 < cols) {
                try writer.writeAll(",");
            }
        }
        try writer.writeAll("\\n");
    }
}

fn writeCsvValue(writer: anytype, value: []const u8) !void {
    const needs_quotes = std.mem.indexOfAny(u8, value, ",\"\n\r") != null;
    if (!needs_quotes) {
        try writer.writeAll(value);
        return;
    }
    try writer.writeAll("\"");
    var i: usize = 0;
    while (i < value.len) : (i += 1) {
        if (value[i] == '"') {
            try writer.writeAll("\"\"");
        } else {
            try writer.writeByte(value[i]);
        }
    }
    try writer.writeAll("\"");
}

test "parseOptions handles key value pairs" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const args = [_][]const u8{ "--cohort", "Spring", "--week", "3" };
    var opts = try parseOptions(allocator, args[0..]);
    defer opts.deinit();

    try std.testing.expectEqualStrings("Spring", opts.get("cohort").?);
    try std.testing.expectEqualStrings("3", opts.get("week").?);
}

test "writeCsvValue escapes quotes and commas" {
    var buffer: [128]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buffer);
    try writeCsvValue(stream.writer(), "Ready, set \"go\"");
    try std.testing.expectEqualStrings("\"Ready, set \"\"go\"\"\"", stream.getWritten());
}
