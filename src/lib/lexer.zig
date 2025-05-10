const std = @import("std");
const testing = std.testing;

pub const Symbol = enum {
    anyCharacter,
    pipe,
    lParen,
    rParen,
    character,
    zeroOrMore,
    oneOrMore,
    zeroOrOne,
};

pub const Token = struct {
    symbol: Symbol,
    letter: u32,
};

pub fn lex(input: []const u8, allocator: std.mem.Allocator) ![]Token {
    var tokens = std.ArrayList(Token).init(allocator);
    var runeIter = (try std.unicode.Utf8View.init(input)).iterator();
    while (runeIter.nextCodepoint()) |r| {
        try tokens.append(lexRune(r));
    }
    return tokens.toOwnedSlice();
}

fn lexRune(r: u32) Token {
    return .{
        .symbol = switch (r) {
            '(' => .lParen,
            ')' => .rParen,
            '.' => .anyCharacter,
            '|' => .pipe,
            '*' => .zeroOrMore,
            '+' => .oneOrMore,
            '?' => .zeroOrOne,
            else => .character,
        },
        .letter = r,
    };
}

test "abc" {
    const allocator = testing.allocator;
    const tokens = try lex("abc", allocator);
    defer allocator.free(tokens);

    const expected = [_]Token{
        .{ .symbol = .character, .letter = 'a' },
        .{ .symbol = .character, .letter = 'b' },
        .{ .symbol = .character, .letter = 'c' },
    };
    try testing.expectEqualSlices(Token, expected[0..expected.len], tokens);
}
