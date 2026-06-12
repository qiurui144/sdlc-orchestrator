# <feature> Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development or superpowers:executing-plans.

**Goal:** <one sentence>

**Architecture:** <2-3 sentences>

**Tech Stack:** <libs>

**Source spec:** `docs/superpowers/specs/<date>-<slug>.md` (commit `<sha>`)

---

## Pre-flight

- [ ] Step 0a: Verify cwd / branch / disk
- [ ] Step 0b: Check tool availability

## Task N: <component>

**Files:**

- Create: `<exact path>`
- Modify: `<exact path>:<lines>`
- Test: `<exact test path>`

### Step N.1: Write the failing test

```<lang>
<full test code>
```

### Step N.2: Run test to verify it fails

Run: `<exact command>`
Expected: FAIL with `<message>`

### Step N.3: Write minimal implementation

```<lang>
<full implementation code>
```

### Step N.4: Run test to verify pass

Run: `<exact command>`
Expected: PASS

### Step N.5: Commit

```bash
git add <files>
git -c user.email=<real-email> commit -m "feat: <summary>

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
```

## Risk register carry-over

<from spec §11>

## GA acceptance checklist

<per spec §7.2 RC 4 gates>
