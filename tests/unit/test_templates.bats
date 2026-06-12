#!/usr/bin/env bats

TPL="$BATS_TEST_DIRNAME/../../templates"

@test "spec-template has all 11 sections" {
  for n in "1. 目标定位" "2. 范围边界" "3. 架构数据流" "4. 模块边界" "5. API 契约" "6. 扩展点" "7. 错误" "8. 成本契约" "9. 测试矩阵" "10. 向后兼容" "11. 风险登记"; do
    grep -q "$n" "$TPL/spec-template.md" || { echo "missing: $n" >&2; return 1; }
  done
}

@test "release-template has 4 mandatory sections" {
  for n in "Highlights" "Breaking" "Migration" "Known Limitations"; do
    grep -q "$n" "$TPL/release-template.md" || { echo "missing: $n" >&2; return 1; }
  done
}

@test "dispatch-template enforces whitelist + Pre-Create Gate" {
  grep -q "Pre-Create Gate" "$TPL/dispatch-template.md"
  grep -q "白名单" "$TPL/dispatch-template.md"
  grep -q "Write" "$TPL/dispatch-template.md"
}

@test "plan-template has TDD step pattern" {
  grep -q "Write the failing test" "$TPL/plan-template.md"
  grep -q "Commit" "$TPL/plan-template.md"
}
