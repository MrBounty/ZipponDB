const std = @import("std");
const Allocator = std.mem.Allocator;
const Parser = @import("ziql/parser.zig");
const Tokenizer = @import("ziql/tokenizer.zig").Tokenizer;
const DBEngine = @import("cli/core.zig");
const ZipponError = @import("error").ZipponError;

const DB = struct {
    path: []const u8,
    schema: []const u8,
};

test "Synthax error" {
    const db = DB{ .path = "test1", .schema = "schema/test" };
    try expectParsingError(db, "ADD User (name = 'Bob', email='bob@email.com', age=-55, scores=[ 1 ], best_friend=7db1f06d-a5a7-4917-8cc6-4d490191c9c1, bday=2000/01/01, a_time=12:04:54.8741, last_order=2000/01/01-12:45)", ZipponError.SynthaxError);
    try expectParsingError(db, "GRAB {}", ZipponError.StructNotFound);
    try expectParsingError(db, "GRAB User {qwe = 'qwe'}", ZipponError.MemberNotFound);
    try expectParsingError(db, "ADD User (name='Bob')", ZipponError.MemberMissing);
    try expectParsingError(db, "GRAB User {name='Bob'", ZipponError.SynthaxError);
    try expectParsingError(db, "GRAB User {age = 50 name='Bob'}", ZipponError.SynthaxError);
    try expectParsingError(db, "GRAB User {age <14 AND (age>55}", ZipponError.SynthaxError);
    try expectParsingError(db, "GRAB User {name < 'Hello'}", ZipponError.ConditionError);
}

test "Clear" {
    const db = DB{ .path = "test1", .schema = "schema/test" };
    try testParsing(db, "DELETE User {}");
}

test "ADD" {
    const db = DB{ .path = "test1", .schema = "schema/test" };
    try testParsing(db, "ADD User (name = 'Bob', email='bob@email.com', age=55, scores=[ 1 ], best_friend=none, friends=none, bday=2000/01/01, a_time=12:04, last_order=2000/01/01-12:45)");
    try testParsing(db, "ADD User (name = 'Bob', email='bob@email.com', age=55, scores=[ 666 123 331 ], best_friend=none, friends=none, bday=2000/11/01, a_time=12:04:54, last_order=2000/01/01-12:45)");
    try testParsing(db, "ADD User (name = 'Bob', email='bob@email.com', age=-55, scores=[ 33 ], best_friend=none, friends=none, bday=2000/01/04, a_time=12:04:54.8741, last_order=2000/01/01-12:45)");
    try testParsing(db, "ADD User (name = 'Boba', email='boba@email.com', age=20, scores=[ ], best_friend=none, friends=none, bday=2000/06/06, a_time=04:04:54.8741, last_order=2000/01/01-12:45)");

    try testParsing(db, "ADD User (name = 'Bob', email='bob@email.com', age=-55, scores=[ 1 ], best_friend={name='Bob'}, friends=none, bday=2000/01/01, a_time=12:04:54.8741, last_order=2000/01/01-12:45)");
    try testParsing(db, "ADD User (name = 'Bou', email='bob@email.com', age=66, scores=[ 1 ], best_friend={name = 'Boba'}, friends={name = 'Bob'}, bday=2000/01/01, a_time=02:04:54.8741, last_order=2000/01/01-12:45)");
    try testParsing(db, "ADD User (name = 'Bobibou', email='bob@email.com', age=66, scores=[ 1 ], best_friend={name = 'Boba'}, friends=[1]{name = 'Bob'}, bday=2000/01/01, a_time=02:04:54.8741, last_order=2000/01/01-12:45)");

    try testParsing(db, "GRAB User {}");
}

test "ADD batch" {
    const db = DB{ .path = "test1", .schema = "schema/test" };
    try testParsing(db, "ADD User (name = 'ewq', email='ewq@email.com', age=22, scores=[ ], best_friend=none, friends=none, bday=2000/01/01, a_time=12:04, last_order=2000/01/01-12:45) (name = 'Roger', email='roger@email.com', age=10, scores=[ 1 11 111 123 562345 123451234 34623465234 12341234 ], best_friend=none, friends=none, bday=2000/01/01, a_time=12:04, last_order=2000/01/01-12:45)");
    try testParsing(db, "ADD User (name = 'qwe', email='qwe@email.com', age=57, scores=[ ], best_friend=none, friends=none, bday=2000/01/01, a_time=12:04, last_order=2000/01/01-12:45) ('Rodrigo', 'bob@email.com', 55, [ 1 ], {name = 'qwe'}, none, 2000/01/01, 12:04, 2000/01/01-12:45)");

    try testParsing(db, "GRAB User [name, best_friend] {name = 'Rodrigo'}");
    try testParsing(db, "GRAB User {}");
}

test "GRAB filter with string" {
    const db = DB{ .path = "test1", .schema = "schema/test" };
    try testParsing(db, "GRAB User {name = 'Bob'}");
    try testParsing(db, "GRAB User {name != 'Brittany Rogers'}");
}

test "GRAB with additional data" {
    const db = DB{ .path = "test1", .schema = "schema/test" };
    try testParsing(db, "GRAB User [1] {age < 18}");
    try testParsing(db, "GRAB User [id, name] {age < 18}");
    try testParsing(db, "GRAB User [100; name, age] {age < 18}");
}

test "UPDATE" {
    const db = DB{ .path = "test1", .schema = "schema/test" };
    try testParsing(db, "UPDATE User [1] {name = 'Bob'} TO (email='new@gmail.com')");
    try testParsing(db, "GRAB User {}");
}

test "GRAB filter with int" {
    const db = DB{ .path = "test1", .schema = "schema/test" };
    try testParsing(db, "GRAB User {age = 18}");
    try testParsing(db, "GRAB User {age > -18}");
    try testParsing(db, "GRAB User {age < 18}");
    try testParsing(db, "GRAB User {age <= 18}");
    try testParsing(db, "GRAB User {age >= 18}");
    try testParsing(db, "GRAB User {age != 18}");
}

test "GRAB filter with date" {
    const db = DB{ .path = "test1", .schema = "schema/test" };
    try testParsing(db, "GRAB User {bday > 2000/01/01}");
    try testParsing(db, "GRAB User {a_time < 08:00}");
    try testParsing(db, "GRAB User {last_order > 2000/01/01-12:45}");
}

test "Specific query" {
    const db = DB{ .path = "test1", .schema = "schema/test" };
    try testParsing(db, "GRAB User");
    try testParsing(db, "GRAB User {}");
    try testParsing(db, "GRAB User [1]");
}

test "UPDATE relationship" {
    const db = DB{ .path = "test1", .schema = "schema/test" };
    try testParsing(db, "UPDATE User [1] {name='Bob'} TO (best_friend = {name='Boba'} )");
    try testParsing(db, "GRAB User {}");
}

test "GRAB Relationship Filter" {
    const db = DB{ .path = "test1", .schema = "schema/test" };
    try testParsing(db, "GRAB User {best_friend IN {name = 'Bob'}}");
    try testParsing(db, "GRAB User {best_friend IN {name = 'Boba'}}");
}

test "GRAB Relationship AdditionalData" {
    const db = DB{ .path = "test1", .schema = "schema/test" };
    try testParsing(db, "GRAB User [name, friends] {}");
    try testParsing(db, "GRAB User [name, best_friend] {}");
}

test "GRAB Relationship Sub AdditionalData" {
    const db = DB{ .path = "test1", .schema = "schema/test" };
    try testParsing(db, "GRAB User [name, friends [name]] {}");
    try testParsing(db, "GRAB User [name, best_friend [name, friends [age]]] {}");
}

test "GRAB Relationship AdditionalData Filtered" {
    const db = DB{ .path = "test1", .schema = "schema/test" };
    try testParsing(db, "GRAB User [2; name, best_friend] {name = 'Bob'}");
    try testParsing(db, "GRAB User [2; name, best_friend] {best_friend IN {}}");
    try testParsing(db, "GRAB User [2; name, best_friend] {best_friend !IN {}}");
}

test "GRAB name IN" {
    const db = DB{ .path = "test1", .schema = "schema/test" };
    try testParsing(db, "GRAB User {name IN ['Bob' 'Bobinou']}");
}

test "GRAB Relationship dot" {
    // DO I add this ? I'm not sure about this feature
    const db = DB{ .path = "test1", .schema = "schema/test" };
    // try testParsing(db, "GRAB User.best_friend {}");
    // try testParsing(db, "GRAB User.best_friend.best_friend {}");
    // try testParsing(db, "GRAB User.best_friend.posts {}");
    // try testParsing(db, "GRAB User.best_friend.posts.comments {}");
    try testParsing(db, "GRAB User [1] {}");
}

test "DELETE" {
    const db = DB{ .path = "test1", .schema = "schema/test" };
    try testParsing(db, "DELETE User {}");
}

test "3 struct base" {
    const db = DB{ .path = "test2", .schema = "schema/test-3struct" };
    try testParsing(db, "DELETE User {}");
    try testParsing(db, "DELETE Post {}");
    try testParsing(db, "ADD User (name = 'Bob', email='bob@email.com', age=55, friends=none, posts=none, comments=none, bday=2000/01/01)");
    try testParsing(db, "ADD Post (text = 'Hello every body', at=NOW, from={}, comments=none)");
    try testParsing(db, "ADD Post (text = 'Hello every body', at=NOW, from={}, comments=none)");
    try testParsing(db, "GRAB Post [id, text, at, from [id, name]] {}");
}

test "3 struct both side" {
    const db = DB{ .path = "test2", .schema = "schema/test-3struct" };
    try testParsing(db, "DELETE User {}");
    try testParsing(db, "DELETE Post {}");
    try testParsing(db, "ADD User (name = 'Bob', email='bob@email.com', age=55, friends=none, posts=none, comments=none, bday=2000/01/01)");
    try testParsing(db, "ADD Post (text = 'Hello every body', at=NOW, from=none, comments=none)");
    //try testParsing(db, "ADD Post (text = 'Hello every body', at=NOW, from={}, comments=none) -> new_post -> UPDATE User {} TO (posts APPEND new_post)");
    // try testParsing(db, "ADD Post (text = 'Hello every body', at=NOW, from={} APPEND TO posts, comments=none)"); Maybe I can use that to be like the above query
    // ADD Post (text = 'Hello every body', at=NOW, from={} TO last_post, comments=none) And this for a single link
    // try testParsing(db, "ADD Post (text = 'Hello every body', at=NOW, from={} APPEND TO [posts, last_post], comments=none)"); Can be an array to add it to multiple list
    // last_post is replaced instead of append
    try testParsing(db, "GRAB Post [id, text, at, from [id, name]] {}");
    try testParsing(db, "GRAB User [id, name] {}");
}

fn testParsing(db: DB, source: [:0]const u8) !void {
    const allocator = std.testing.allocator;
    var db_engine = DBEngine.init(allocator, db.path, db.schema);
    defer db_engine.deinit();

    var parser = Parser.init(
        &db_engine.file_engine,
        &db_engine.schema_engine,
    );

    std.debug.print("Running: {s}\n", .{source});
    try parser.parse(allocator, source);
    std.debug.print("\n\n-------------------------------\n\n", .{});
}

fn expectParsingError(db: DB, source: [:0]const u8, err: ZipponError) !void {
    const allocator = std.testing.allocator;
    var db_engine = DBEngine.init(allocator, db.path, db.schema);
    defer db_engine.deinit();

    var parser = Parser.init(
        &db_engine.file_engine,
        &db_engine.schema_engine,
    );

    std.debug.print("Running: {s}\n", .{source});
    try std.testing.expectError(err, parser.parse(allocator, source));
    std.debug.print("\n\n-------------------------------\n\n", .{});
}
