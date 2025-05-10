const std = @import("std");
const testing = std.testing;

const ast = @import("lib/ast.zig");
const fsm = @import("lib/fsm.zig");
const lexer = @import("lib/lexer.zig");
const Parser = @import("lib/Parser.zig");

pub const Regex = struct {
    s: *fsm.State,
    node: ast.Node,

    pub fn init(allocator: std.mem.Allocator, re: []const u8) !*Regex {
        const tokens = try lexer.lex(re, allocator);
        defer allocator.free(tokens);

        var parser = Parser.init();
        defer parser.deinit();

        // literal node 编译出的 state 通过 predicator 持有 node 的指针
        // 所以 node 必须在　state 之后释放
        var node = try parser.parse(allocator, tokens);

        const compiled = try node.compile(allocator);

        const r = try allocator.create(Regex);
        r.s = compiled.start;
        r.node = node;

        return r;
    }

    pub fn deinit(self: *Regex, allocator: std.mem.Allocator) void {
        self.s.deinit(allocator);
        self.node.deinit();
        allocator.destroy(self);
    }

    pub fn match(self: *Regex, input: []const u8) !bool {
        var runner = fsm.Runner.init(self.s);
        var runeIter = (try std.unicode.Utf8View.init(input)).iterator();
        while (runeIter.nextCodepoint()) |r| {
            runner.next(r);
        }
        return runner.getStatus() == .success;
    }
};

test "root" {
    testing.refAllDecls(@import("lib/ast.zig"));
    testing.refAllDecls(@import("lib/fsm.zig"));
    testing.refAllDecls(@import("lib/lexer.zig"));
    testing.refAllDecls(@import("lib/Parser.zig"));
}

test "regex" {
    const allocator = testing.allocator;

    const regex = try Regex.init(allocator, "abc");
    defer regex.deinit(allocator);

    const match = try regex.match("abc");
    try testing.expect(match);
}
