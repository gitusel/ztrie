const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const allocPrintZ = std.fmt.allocPrintZ;
const cwd = std.fs.cwd();
const File = std.fs.File;
const bufferedWriter = std.io.bufferedWriter;
const stdout_writer = std.io.getStdOut().writer();
const stderr_writer = std.io.getStdErr().writer();
const WriteError = std.os.WriteError;
const eql = std.mem.eql;
const ChildProcess = std.ChildProcess;
const Term = ChildProcess.Term;

const CString = [:0]const u8;
const buffer_size: usize = 4096;
const FileWriter = std.io.Writer(std.fs.File, std.os.WriteError, std.fs.File.write);
const BufferedWriterFileWriter = std.io.BufferedWriter(buffer_size, FileWriter);
const BufferedFileWriter = std.io.Writer(*BufferedWriterFileWriter, std.os.WriteError, BufferedWriterFileWriter.write);

// trie
const Node = struct {
    value: u8,
    text: CString,
    end: bool,
    index: u32,
    parent_index: u32,
    children: ArrayList(*Node),
};

// stack
const SNode = struct { node: *Node, next: ?*SNode };

fn newSNode(allocator: Allocator, node: *Node) error{OutOfMemory}!*SNode {
    var stack_node: *SNode = try allocator.create(SNode);
    stack_node.node = node;
    stack_node.next = null;
    return stack_node;
}

const Stack = struct { head: ?*SNode, size: usize };

fn newStack(allocator: Allocator) error{OutOfMemory}!*Stack {
    var stack: *Stack = try allocator.create(Stack);
    stack.head = null;
    stack.size = 0;
    return stack;
}

fn push(allocator: Allocator, stack: *Stack, node: *Node) error{OutOfMemory}!void {
    var new_head: *SNode = try newSNode(allocator, node);
    new_head.next = stack.head;
    stack.head = new_head;
    stack.size += 1;
}

fn pop(allocator: Allocator, stack: *Stack) ?*Node {
    if (stack.size == 0) {
        return null;
    }
    var head: *SNode = stack.head.?;
    stack.head = head.next;
    stack.size -= 1;
    var node: *Node = head.node;
    allocator.destroy(head);
    return node;
}

fn freeAllSNodes(allocator: Allocator, stack: *Stack) void {
    if (stack.head) |head| {
        var stack_node: ?*SNode = head;
        while (stack_node) |snode| {
            stack_node = snode.next;
            allocator.destroy(snode);
        }
    }
}

fn pushAllTrieNodes(allocator: Allocator, stack: *Stack, node: *Node) error{OutOfMemory}!void {
    // DFS
    for (node.children.items) |child| {
        try pushAllTrieNodes(allocator, stack, child);
    }
    try push(allocator, stack, node);
}

// data
const fruits = [_]CString{ "Apple", "Apricot", "Avocado", "Banana", "Bilberry", "Blackberry", "Blackcurrant", "Blueberry", "Boysenberry", "Currant", "Cherry", "Cherimoya", "Chico fruit", "Cloudberry", "Coconut", "Cranberry", "Cucumber", "Custard apple", "Damson", "Date", "Dragonfruit", "Durian", "Elderberry", "Feijoa", "Fig", "Goji berry", "Gooseberry", "Grape", "Raisin", "Grapefruit", "Guava", "Honeyberry", "Huckleberry", "Jabuticaba", "Jackfruit", "Jambul", "Jujube", "Juniper berry", "Kiwano", "Kiwifruit", "Kumquat", "Lemon", "Lime", "Loquat", "Longan", "Lychee", "Mango", "Mangosteen", "Marionberry", "Melon", "Cantaloupe", "Honeydew", "Watermelon", "Miracle fruit", "Mulberry", "Nectarine", "Nance", "Olive", "Orange", "Blood orange", "Clementine", "Mandarine", "Tangerine", "Papaya", "Passionfruit", "Peach", "Pear", "Persimmon", "Physalis", "Plantain", "Plum", "Prune", "Pineapple", "Plumcot", "Pomegranate", "Pomelo", "Purple mangosteen", "Quince", "Raspberry", "Salmonberry", "Rambutan", "Redcurrant", "Salal berry", "Salak", "Satsuma", "Soursop", "Star fruit", "Solanum quitoense", "Strawberry", "Tamarillo", "Tamarind", "Ugli fruit", "Yuzu" };

// utilities
inline fn print_out(comptime format: []const u8, args: anytype) void {
    stdout_writer.print(format, args) catch {};
}

inline fn print_err(comptime format: []const u8, args: anytype) void {
    stderr_writer.print(format, args) catch {};
}

// trie methods
fn newTrieNode(allocator: Allocator, value: u8, text: CString, end: bool) !*Node {
    const Static = struct {
        var count: u32 = 0;
    };
    var node: *Node = try allocator.create(Node);
    node.value = value;
    node.text = text;
    node.end = end;
    node.index = Static.count;
    node.parent_index = 0;
    Static.count += 1;
    node.children = ArrayList(*Node).init(allocator);
    return node;
}

fn trieFind(root: *Node, text: CString) ?*Node {
    var node: *Node = root;
    for (text) |char| {
        var found_in_child = false;
        for (node.children.items) |child| {
            if (child.value == char) {
                node = child;
                found_in_child = true;
                break; // for loop
            }
        }
        if (!found_in_child) {
            return null;
        }
    }
    return node;
}

fn trieDelete(allocator: Allocator, root: *Node, text: CString) !void {
    if (text.len == 0) {
        return;
    }

    var result = trieDeleteHelper(allocator, root, text);
    var text_len: usize = text.len;

    while (true) {
        if (result == null) break;
        text_len -= 1;
        if (text_len > 0) {
            const new_text = try allocPrintZ(allocator, "{s}", .{text[0..text_len]});
            defer allocator.free(new_text);
            result = trieDeleteHelper(allocator, root, new_text);
        } else {
            break;
        }
    }
}

fn trieDeleteHelper(allocator: Allocator, root: *Node, text: CString) ?*Node {
    var previous_node: *Node = root;
    var node_to_remove_index: usize = 0;
    var node: *Node = root;
    if (text.len == 0) {
        return null;
    }
    for (text) |char| {
        var found_in_child = false;
        var index: usize = 0;
        const node_children_len: usize = node.children.len;
        while (index < node_children_len) : (index += 1) {
            const child = node.children.items[index];
            //     for (node.children.items, 0..) |child, index| {
            if (child.value == char) {
                previous_node = node;
                node_to_remove_index = index;
                node = child;
                found_in_child = true;
                break; // for loop
            }
        }
        if (!found_in_child) {
            return null;
        }
    }

    // if no more children nodes then we could remove the node else we remove the word
    if (node.children.items.len == 0) {
        // remove node
        _ = previous_node.children.orderedRemove(node_to_remove_index);
        freeAllTrieNodes(allocator, node);
        if ((previous_node.children.items.len == 0) and (!previous_node.end)) {
            return previous_node;
        }
    } else {
        node.end = false;
        node.text = "";
    }
    return null;
}

fn trieInsert(allocator: Allocator, root: *Node, text: CString) !void {
    var node: *Node = root;
    for (text) |char| {
        if (node.children.capacity == 0) {
            var new_node: *Node = try newTrieNode(allocator, char, "", false);
            new_node.parent_index = node.index;
            try node.children.append(new_node);
            node = new_node;
        } else {
            var found_in_child = false;
            for (node.children.items) |child| {
                if (child.value == char) {
                    node = child;
                    found_in_child = true;
                    break; // for loop
                }
            }
            if (!found_in_child) {
                var new_node: *Node = try newTrieNode(allocator, char, "", false);
                new_node.parent_index = node.index;
                try node.children.append(new_node);
                node = new_node;
            }
        }
    }
    node.text = text;
    node.end = true;
}

fn freeAllTrieNodes(allocator: Allocator, node: *Node) void {
    // DFS
    for (node.children.items) |child| {
        freeAllTrieNodes(allocator, child);
    }
    // if at the leaf no more children so we can clear
    node.children.clearAndFree();
    allocator.destroy(node);
}

// commands
// dot
fn dumpDot(allocator: Allocator, node: *Node, buffered_file_writer: BufferedFileWriter) anyerror!void {
    // DFS iteractive
    var stack = try newStack(allocator);
    defer allocator.destroy(stack);

    try push(allocator, stack, node);

    while (stack.size != 0) {
        var stack_node: *Node = pop(allocator, stack).?; // should never be null in this case
        if (stack_node.value != 0) {
            try buffered_file_writer.print("    Node_{d} [label=\"{c}\"]\n", .{ stack_node.index, stack_node.value });
            try buffered_file_writer.print("    Node_{d} -> Node_{d} [label=\"{c}\"]\n", .{ stack_node.parent_index, stack_node.index, stack_node.value });
        }

        // push on the stack in reverse order
        var index: usize = stack_node.children.items.len;
        while (index != 0) {
            index -= 1;
            try push(allocator, stack, stack_node.children.items[index]);
        }
    }
}

fn dot(allocator: Allocator, root: *Node, args: [][:0]u8) anyerror!void {
    _ = args;
    const output_filepath: CString = "trie.dot";
    print_out("INFO: Generating {s}\n", .{output_filepath});
    const file: File = cwd.createFile(output_filepath, .{}) catch |err| {
        print_err("ERROR: could not create file {s} : {}\n", .{ output_filepath, err });
        return;
    };
    defer file.close();

    const writer: FileWriter = file.writer();
    var buffered_writer: BufferedWriterFileWriter = bufferedWriter(writer);
    var buffered_file_writer: BufferedFileWriter = buffered_writer.writer();

    // writing file
    try buffered_file_writer.writeAll("digraph Trie {\n");
    try buffered_file_writer.print("    Node_{d} [label={s}]\n", .{ 0, "root" });
    try dumpDot(allocator, root, buffered_file_writer);
    try buffered_file_writer.writeAll("}");
    buffered_writer.flush() catch |err| {
        print_err("ERROR: could not write buffered data to file {s} : {}\n", .{ output_filepath, err });
    };

    // convert dot to svg
    print_out("INFO: Generating {s}.svg using dot command\n", .{output_filepath});

    var dot_command: ChildProcess = ChildProcess.init(&[_][]const u8{ "dot", "-Tsvg", output_filepath, "-O" }, allocator);
    const result_dot_command: Term = try dot_command.spawnAndWait();
    switch (result_dot_command) {
        .Exited => |code| {
            if (code != 0) {
                print_err("ERROR: command exited with error code {d}\n", .{code});
            } else {
                print_out("INFO: done\n", .{});
            }
        },
        else => {
            print_err("ERROR: command exited unexpectedly\n", .{});
        },
    }
}

// complete
fn autoComplete(node: *Node) void {
    // DFS recursive
    for (node.children.items) |child| {
        autoComplete(child);
    }
    if (node.end) {
        print_out("{s}\n", .{node.text});
    }
}

fn complete(allocator: Allocator, root: *Node, args: [][:0]u8) anyerror!void {
    _ = allocator;
    const node: ?*Node = trieFind(root, args[1]);
    if (node) |n| {
        autoComplete(n);
    } else {
        print_out("No autocomplete suggestions found\n", .{});
    }
}

pub fn main() anyerror!void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    // get arguments
    const argv: [][:0]u8 = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, argv);

    if ((argv.len == 1) or ((argv.len == 2) and (!eql(u8, argv[1], "dot"))) or ((argv.len == 3) and (!eql(u8, argv[1], "complete")))) {
        print_out(
            \\ usage: {s} <SUBCOMMAND>
            \\ SUBCOMMANDS:
            \\ dot                Dump the Trie into a Graphviz dot file.
            \\ complete <prefix>  Suggest prefix autocompletion based on the Trie.
        ++ "\n", .{argv[0]});
        return;
    }

    const commands = std.ComptimeStringMap(*const fn (std.mem.Allocator, *Node, [][:0]u8) anyerror!void, .{
        .{ "dot", dot },
        .{ "complete", complete },
    });

    var root: *Node = try newTrieNode(allocator, 0, "", false);
    defer freeAllTrieNodes(allocator, root);

    // load data
    for (fruits) |fruit| {
        try trieInsert(allocator, root, fruit);
    }

    const command = commands.get(argv[1]);

    try command.?(allocator, root, argv[1..]);
}

test "trieInsert / trieFind" {
    const expect = std.testing.expect;
    const test_allocator = std.testing.allocator;
    var root: *Node = try newTrieNode(test_allocator, 0, "", false);
    defer freeAllTrieNodes(test_allocator, root);
    try trieInsert(test_allocator, root, "worla");
    try trieInsert(test_allocator, root, "worlb");
    try trieInsert(test_allocator, root, "worlc");
    try trieInsert(test_allocator, root, "world");
    const node: ?*Node = trieFind(root, "worlc");
    try expect(eql(u8, node.?.text, "worlc"));
}

test "trieDelete" {
    const expect = std.testing.expect;
    const test_allocator = std.testing.allocator;
    var root: *Node = try newTrieNode(test_allocator, 0, "", false);
    defer freeAllTrieNodes(test_allocator, root);
    try trieInsert(test_allocator, root, "worla");
    try trieInsert(test_allocator, root, "worlb");
    try trieInsert(test_allocator, root, "worlc");
    try trieInsert(test_allocator, root, "world");
    try trieDelete(test_allocator, root, "worlb");
    const node: ?*Node = trieFind(root, "worlb");
    try expect(node == null);
}

test "autoComplete" {
    const expect = std.testing.expect;
    const test_allocator = std.testing.allocator;
    var root: *Node = try newTrieNode(test_allocator, 0, "", false);
    defer freeAllTrieNodes(test_allocator, root);
    try trieInsert(test_allocator, root, "worla");
    try trieInsert(test_allocator, root, "worlb");
    try trieInsert(test_allocator, root, "worlc");
    try trieInsert(test_allocator, root, "world");
    var node: ?*Node = trieFind(root, "worl");
    try expect(node != null);
    node = trieFind(root, "zzz");
    try expect(node == null);
}

test "node stack" {
    const expect = std.testing.expect;
    const test_allocator = std.testing.allocator;
    var root: *Node = try newTrieNode(test_allocator, 0, "", false);
    defer freeAllTrieNodes(test_allocator, root);

    try trieInsert(test_allocator, root, "abd");
    try trieInsert(test_allocator, root, "abeh");
    try trieInsert(test_allocator, root, "acf");
    try trieInsert(test_allocator, root, "acg");

    var stack: *Stack = try newStack(test_allocator);
    defer test_allocator.destroy(stack);
    defer freeAllSNodes(test_allocator, stack);
    try pushAllTrieNodes(test_allocator, stack, root);
    while (stack.size != 0) {
        _ = pop(test_allocator, stack);
    }
    try expect(stack.head == null);
}
