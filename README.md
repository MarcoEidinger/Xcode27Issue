# Xcode27Issue

iOS app in `Xcode27Issue.xcodeproj` that depends on the local Swift package
`cloud-sdk-ios-fiori-26.8.4` (SAP Fiori for iOS).

- ✅ Compiles **and links** with Xcode 26.0.1 (17A400) — see `Xcode26CompilationResults/`.
- ❌ Originally **failed to link** with Xcode 27.1 (27A9275, Swift 6.4) — see `Xcode27CompilationResults/`.
- ✅ **Fixed** — now links with Xcode 27.1 after the source change described below. See `FixCompilationResults/` for a successful Xcode 27.1 build log.

## Original linker error (Xcode 27.1)

```
Undefined symbols for architecture arm64:
  "variable initialization expression of FioriSwiftUICore._ObjectHeader.(_leftViewSize in _45A7…) : SwiftUI.State<__C.CGSize>", referenced from:
      (extension in FioriSwiftUICore):FioriSwiftUICore._ObjectHeader<…>.init(title:subtitle:…)
  … same for _mainViewSize, _rightViewSize, _middleViewSize, _statusViewSize, _currentTabIndex
ld: symbol(s) not found for architecture arm64
Linker command failed with exit code 1
```

## Root cause

The undefined symbols are the **default-value initializers** of six `@State`
properties on `FioriSwiftUICore._ObjectHeader`
(`leftViewSize`, `mainViewSize`, `rightViewSize`, `middleViewSize`,
`statusViewSize`, `currentTabIndex`), declared with inline defaults in
`Sources/FioriSwiftUICore/_generated/ViewModels/API/_ObjectHeader+API.generated.swift`:

```swift
@State var rightViewSize: CGSize = CGSize(width: 120, height: 0)
@State var leftViewSize:  CGSize = CGSize(width: 740, height: 0)
// … etc.
```

A `@State` property's synthesized **backing store** (`_leftViewSize`, …) is
**`private`** — reachable only within the source file that declares it.

The public `_ObjectHeader.init(title:…headerChart:)` lived in a **different** file,
`Sources/FioriSwiftUICore/Views/_ObjectHeader+View.swift`. Because that init does
not assign the `@State` properties, it depends on the compiler-synthesized
default-value initializers of those private backing stores — **across the file
boundary**.

- **Xcode 26 / Swift 6.1** emitted a thunk that let that cross-file dependency
  resolve at link time → the build succeeded.
- **Xcode 27 / Swift 6.4** no longer emits/exports that thunk in a linkable form →
  the linker can't find `_leftViewSize` et al. → `Undefined symbols`.

The two initializers in `_ObjectHeader+API.generated.swift` were never affected
because they are in the **same file** as the declarations, so their default-value
initializers resolve locally.

> Investigated and ruled out: forcing whole-module compilation of `FioriSwiftUICore`
> does **not** fix it — confirming the problem is symbol emission/visibility, not
> object-file layout. Full attempt-by-attempt log is in
> [`FIX_ATTEMPTS.md`](FIX_ATTEMPTS.md).

## Fix

Co-locate the failing initializer with the property declarations so the `@State`
defaults resolve within a single file and no cross-file symbol is needed. No API,
signature, access-level, generic-constraint, or runtime-behaviour change — the
initializer only moved source files.

1. **Removed** `init(title:…headerChart:)` from
   `Sources/FioriSwiftUICore/Views/_ObjectHeader+View.swift` (left a comment in its place).
2. **Added** that same initializer — verbatim body — to
   `Sources/FioriSwiftUICore/_generated/ViewModels/API/_ObjectHeader+API.generated.swift`
   as its own `public extension _ObjectHeader where … DetailContent == HeaderChart`.
3. Kept the inline `@State` defaults on the declarations.

No changes to the app target, `Package.swift`, or build settings.

### Verification

Clean full rebuild from empty DerivedData with Xcode 27.1:

```
$ xcodebuild clean -project Xcode27Issue.xcodeproj -scheme Xcode27Issue
$ xcodebuild build -project Xcode27Issue.xcodeproj -scheme Xcode27Issue \
      -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -configuration Debug
** BUILD SUCCEEDED ** [191.5 sec]
```

---

## Note to `cloud-sdk-ios-fiori` maintainers

> **Draft** — intended for the SAP `cloud-sdk-ios-fiori` team. The fix above was
> applied to a **vendored copy** (`cloud-sdk-ios-fiori-26.8.4/`) to unblock an app
> building with Xcode 27.1 / Swift 6.4. It needs a proper home upstream.

**Problem.** Building any consumer of `FioriSwiftUICore` with **Xcode 27.1
(Swift 6.4)** fails at link time with `Undefined symbols … variable initialization
expression of FioriSwiftUICore._ObjectHeader.(_leftViewSize …) : SwiftUI.State<…>`
(and the five sibling `@State` properties). The same project links cleanly with
Xcode 26.0.1 (Swift 6.1).

**Why.** `_ObjectHeader`'s `@State` properties are declared with inline defaults in
`_ObjectHeader+API.generated.swift`, but the public `init(title:…headerChart:)` is
hand-written in a *different* file, `Views/_ObjectHeader+View.swift`. A `@State`
backing store is `private` (file-scoped), and that init relies on the compiler's
synthesized default-value initializer for those private stores across the file
boundary. Swift 6.4 stopped emitting that cross-file thunk in a linkable form, so
the reference is unresolved. (Whole-module compilation does **not** work around it.)

**Minimal fix we applied.** Move the hand-written `init(title:…headerChart:)` from
`Views/_ObjectHeader+View.swift` into the same file that declares the properties
(`_ObjectHeader+API.generated.swift`). Same-file placement lets the `@State`
defaults resolve locally; no cross-file symbol is emitted. The initializer's
signature, access level, generic constraints, and body are unchanged — purely a
relocation. This almost certainly affects **every** `cloud-sdk-ios-fiori` release,
not just 26.8.4, since the file layout is the same.

**⚠️ Caveat — the target file is Sourcery-generated.**
`_ObjectHeader+API.generated.swift` carries `// Generated using Sourcery … DO NOT EDIT`.
A hand-edit there would be overwritten on the next `sourcery` run, so the fix must
be expressed through the generator, not the output. Options for you to evaluate:

- **Emit the `HeaderChart` convenience initializer from Sourcery** into the same
  generated file as the `@State` declarations (e.g. via the existing
  `// sourcery:` virtual-property annotations / templates in
  `Models/ModelDefinitions.swift` and the `_ObjectHeader` stencil), instead of
  hand-maintaining it in `Views/_ObjectHeader+View.swift`. This matches what we did
  by hand and keeps generated code authoritative.
- **Alternatively, make the init self-sufficient** so it never depends on the
  cross-file default-value thunk — e.g. have every direct initializer assign the
  `@State` stores explicitly. Note this only compiles for initializers in the
  *same* file as the declarations (the private backing store is file-scoped), so in
  practice it still points toward generating the init alongside the declarations.
- Whatever the mechanism, please guard it so a future `sourcery` regeneration keeps
  the initializer and the `@State` declarations in one file.

**Repro.** Open any app depending on `FioriSwiftUICore` that references
`_ObjectHeader` (e.g. via `FioriIcon` + a `Button`, as in this sample's
`ContentView.swift`) and build with Xcode 27.1 for an iOS simulator.

See [`FIX_ATTEMPTS.md`](FIX_ATTEMPTS.md) in this repo for the full diagnosis.
