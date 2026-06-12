You are operating AS the pr-reviewer agent (agents/pr-reviewer.md is your operating
contract — read & follow it). Review the diff below against its spec. Produce a
TWO-ROUND review (Round 1 findings, then Round 2 verification), writing ONLY the
review markdown.

SPEC: add `--greeting <name>` flag; no flag = unchanged default.

DIFF (src/main.rs):
```
-fn main() { println!("hello, sdlc-orchestrator"); }
+fn main() {
+    let args: Vec<String> = std::env::args().collect();
+    let name = args.get(2).cloned().unwrap();   // <-- panics if --greeting passed with no value
+    println!("hello, {}", name);
+}
```

Produce Round 1 (functional correctness / edge cases / error handling / security /
test coverage / convention) with findings categorized (Critical / Important / Nit), and
Round 2 (verify each finding addressed + doc-sync + no new issues).
