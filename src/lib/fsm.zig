const std = @import("std");
const Allocator = std.mem.Allocator;
const testing = std.testing;

const lexer = @import("lexer.zig");
const Parser = @import("Parser.zig");
const ast = @import("ast.zig");

const Status = enum {
    success,
    fail,
    normal,
};

pub const State = struct {
    transitions: std.ArrayList(Transition),

    pub fn init(allocator: std.mem.Allocator) !*State {
        var s = try allocator.create(State);
        s.transitions = std.ArrayList(Transition).init(allocator);
        return s;
    }

    pub fn deinit(self: *State, allocator: Allocator) void {
        for (self.transitions.items) |transition| {
            transition.to.deinit(allocator);
        }
        self.transitions.deinit();
        allocator.destroy(self);
    }

    pub fn isSuccessState(self: State) bool {
        return self.transitions.items.len == 0;
    }

    fn firstMatchingTransition(self: State, input: u32) ?*State {
        for (self.transitions.items) |transition| {
            if (transition.predicator.predicate(input)) {
                return transition.to;
            }
        }

        return null;
    }

    pub fn merge(self: *State, another: *State) Allocator.Error!void {
        for (another.transitions.items) |t| {
            try self.addTransition(t.to, t.predicator);
        }

        another.delete();
    }

    pub fn addTransition(self: *State, to: *State, predicator: Predicator) Allocator.Error!void {
        const tran = Transition{
            .from = self,
            .to = to,
            .predicator = predicator,
        };
        try self.transitions.append(tran);
    }

    pub fn delete(self: *State) void {
        self.transitions.shrinkAndFree(0);
    }
};

pub const Predicator = struct {
    ptr: *anyopaque,
    vtable: struct {
        predicate: *const fn (*anyopaque, input: u32) bool,
    },

    pub fn predicate(self: Predicator, input: u32) bool {
        return self.vtable.predicate(self.ptr, input);
    }
};

pub const Transition = struct {
    from: *State,
    to: *State,
    predicator: Predicator,
};

pub const Runner = struct {
    head: ?*State,
    current: ?*State,

    pub fn init(s: ?*State) Runner {
        return Runner{
            .head = s,
            .current = s,
        };
    }

    pub fn next(self: *Runner, input: u32) void {
        if (self.current) |s| {
            // move to next matching transition
            self.current = s.firstMatchingTransition(input);
        }
        return;
    }

    pub fn getStatus(self: Runner) Status {
        if (self.current) |s| {
            if (s.isSuccessState()) {
                return Status.success;
            }
            return Status.normal;
        } else {
            return Status.fail;
        }
    }
};

const FsmTestCase = struct {
    pattern: []const u8,
    input: []const u8,
    expectedStatus: Status,
};

fn test_fsm(tc: FsmTestCase) !void {
    const log = std.log.scoped(.test_fsm);

    const allocator = std.testing.allocator;

    const tokens = try lexer.lex(tc.pattern, allocator);
    defer allocator.free(tokens);

    var parser = Parser.init();
    defer parser.deinit();

    var node = try parser.parse(allocator, tokens);
    defer node.deinit();
    log.debug("node: {}", .{node});

    const compileResult = try node.compile(allocator);
    const startState = compileResult.start;
    log.debug("start: {}", .{compileResult.start});
    log.debug("end: {}", .{compileResult.end});
    defer startState.deinit(allocator);

    var runner = Runner.init(startState);
    var utf8 = (try std.unicode.Utf8View.init(tc.input)).iterator();
    while (utf8.nextCodepoint()) |c| {
        const preState = runner.getStatus();
        runner.next(c);
        const postState = runner.getStatus();
        log.debug("{} -{}-> {}", .{ preState, c, postState });
    }
    const result = runner.getStatus();
    try testing.expectEqual(tc.expectedStatus, result);
}

test "empty string" {
    try test_fsm(.{
        .pattern = "abc",
        .input = "",
        .expectedStatus = .normal,
    });
}
test "non matching string" {
    try test_fsm(.{
        .pattern = "abc",
        .input = "x",
        .expectedStatus = .fail,
    });
}
test "matching string" {
    try test_fsm(.{
        .pattern = "abc",
        .input = "abc",
        .expectedStatus = .success,
    });
}
test "partial matching string" {
    try test_fsm(.{
        .pattern = "abc",
        .input = "ab",
        .expectedStatus = .normal,
    });
}
test "non matching unicode" {
    try test_fsm(.{
        .pattern = "abc",
        .input = "不行",
        .expectedStatus = .fail,
    });
}
