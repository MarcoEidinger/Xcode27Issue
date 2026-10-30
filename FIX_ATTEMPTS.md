# Xcode 27 Linker Issue — Analysis & Fix Attempts

## Problem

`Xcode27Issue.xcodeproj` compiles successfully with Xcode 26.0.1 but fails to **link**
with Xcode 27.1 (Swift 6.4). The app depends on the local Swift package
`cloud-sdk-ios-fiori-26.8.4` (SAP Fiori for iOS, SwiftUI).

### Linker errors

```
Undefined symbols for architecture arm64:
  "variable initialization expression of FioriSwiftUICore._ObjectHeader.(_leftViewSize in _45A7...) : SwiftUI.State<__C.CGSize>", referenced from:
      (extension in FioriSwiftUICore):FioriSwiftUICore._ObjectHeader<...>.init(title:subtitle:...)
  ... (same for _mainViewSize, _rightViewSize, _middleViewSize, _statusViewSize, _currentTabIndex)
ld: symbol(s) not found for architecture arm64
```

(Full logs: `Xcode27CompilationResults/`, `Xcode26CompilationResults/`.)

## Root-cause analysis

The undefined symbols are the **default-value initializer expressions** of
`@State` stored properties that have inline defaults:

`Sources/FioriSwiftUICore/_generated/ViewModels/API/_ObjectHeader+API.generated.swift`
```swift
public struct _ObjectHeader<...> {
    @State var rightViewSize: CGSize  = CGSize(width: 120, height: 0)
    @State var leftViewSize: CGSize   = CGSize(width: 740, height: 0)
    @State var statusViewSize: CGSize = .zero
    @State var currentTabIndex: Int   = 0
    @State var middleViewSize: CGSize = CGSize(width: 312, height: 0)
    @State var mainViewSize: CGSize   = .zero
    ...
}

// In a *separate* extension that does NOT assign the @State properties:
extension _ObjectHeader where Title == Text, ... {
    public init(title: String, subtitle: String? = nil, ...) {
        self._title = Text(title)
        ...
        // NOTE: never assigns rightViewSize/leftViewSize/... so it relies on
        //       the compiler-emitted default-value initializer symbols.
    }
}
```

When Swift synthesizes a memberwise/explicit `init` in an **extension** that does
not itself initialize every stored property, it emits references to the
per-property **"variable initialization expression"** thunks for the defaulted
properties. Those thunk symbols are produced when compiling the file that
*declares* the property.

In **Swift 6.4 (Xcode 27)** the symbol linkage/visibility of those
default-value initializer thunks for `@State` properties changed. The thunks are
no longer emitted with a linkage that the `init` in the extension can reference
across the generated-file boundary, so the linker reports them as undefined.
Xcode 26 (Swift 6.1) emitted/exported them, so linking succeeded.

This reproduces specifically for `_ObjectHeader` because the public
`init(title:…)` lives in a **separate extension** from the property
declarations and does not assign the `@State` defaults.

## Fix strategy

Make the extension `init` **explicitly assign** every `@State` property to the
same default value it previously relied on being synthesized. This removes the
reference to the external "variable initialization expression" symbols entirely —
the init now initializes the stored properties itself — so there is nothing for
the linker to look up.

This is a source-compatible, behaviour-preserving change (the assigned values are
identical to the former inline defaults).

---

## Attempts

### Attempt 1 — explicitly initialize `@State` defaults inside the extension `init`
**Change:** In `_ObjectHeader+API.generated.swift`, within the
`init(title:subtitle:…)` in the `extension`, assign each `@State` property to the
same literal value as its declared default, e.g.:
```swift
self._rightViewSize  = State(initialValue: CGSize(width: 120, height: 0))
self._leftViewSize   = State(initialValue: CGSize(width: 740, height: 0))
self._statusViewSize = State(initialValue: .zero)
self._currentTabIndex = State(initialValue: 0)
self._middleViewSize = State(initialValue: CGSize(width: 312, height: 0))
self._mainViewSize   = State(initialValue: .zero)
```
**Rationale:** Removes dependence on the externally-emitted default-value
initializer symbol for these `@State` properties.

**Result:** ❌ **FAILED.** Same undefined symbols. Explicitly assigning the
`@State` backing stores with `State(initialValue:)` in the extension init does NOT
remove the compiler's reference to the property's default-value initializer thunk;
the thunk is still emitted as a file-private symbol (`_45A7…` discriminator) and is
still referenced from the recompiled extension init, but not found at link time.
Conclusion: the reference to the default-value thunk is tied to the *declaration*
having an inline default, not to whether the init assigns it.

Baseline confirmed first: clean build with Xcode 27.1 → `BUILD FAILED`, identical
linker errors, reproducible from the command line (`xcodebuild -scheme Xcode27Issue
-destination 'id=<iphone17pro-26.5-sim>'`).

### Attempt 2 — remove the inline defaults from the `@State` declarations and set them in the designated init
**Hypothesis:** If the `@State` properties have **no inline default**, the compiler
emits **no** "variable initialization expression" thunk, so there is no symbol to
reference or fail to link. The values are instead supplied in every init.
**Result:** ⚠️ Linker error **gone**, but surfaced a *compile* error:
`_ObjectHeader+View.swift:36: return from initializer without initializing all
stored properties`. There is a **third** direct initializer — the
`init(title:…headerChart:)` in `_ObjectHeader+View.swift` (the
`DetailContent == HeaderChart` variant, which is the exact init in the original
linker error) — plus potentially others, that relied on the inline `@State`
defaults. Removing the defaults turns the latent link error into a hard compile
error across every init. Patching all of them is invasive and fragile for
generated code. Reverted.

**Important finding from this attempt:** removing the inline defaults *does*
eliminate the undefined-symbol linker error — confirming the root cause is the
default-value initializer thunk, not anything else.

### Attempt 3 — force whole-module compilation for `FioriSwiftUICore` (no source changes)
**Diagnosis refined from the build log:** `FioriSwiftUICore` is compiled with
`-enable-batch-mode -incremental -Onone -disable-cmo` (standard SPM Debug). Under
batch/incremental mode the module is split across multiple object files. The
file-private default-value initializer thunk for the `@State` properties
(discriminator `_45A7…`) is emitted into one object file but referenced from the
extension init compiled into another. In Swift 6.4 (Xcode 27) the linkage of that
thunk regressed so the cross-object-file reference is unresolved → undefined
symbol. Xcode 26 (Swift 6.1) resolved it.

**Hypothesis:** Compiling `FioriSwiftUICore` in **whole-module** mode puts the
thunk and its reference in the *same* object file, so there is no cross-object
symbol to resolve. This needs **no source edits** to the generated code — only a
`swiftSettings` entry on the target in `Package.swift` (allowed because this is a
**local** package, where `unsafeFlags` are permitted).

**Result:** ❌ **FAILED.** First try (`-wmo` via `unsafeFlags`) hit
`index output filenames do not match input source files` because SPM still appends
`-incremental -enable-batch-mode -index-store-path`, which conflict with `-wmo`.
Re-tested with `COMPILER_INDEX_STORE_ENABLE=NO` to remove the index clash and
isolate the question. With a **clean, non-concurrent** build the module compiled
in true whole-module mode (compiler logged *"Incremental compilation has been
disabled … whole module optimization"*) — and the link **still failed with the
same `symbol(s) not found` / undefined `_leftViewSize` etc.**

**Key conclusion:** The undefined-symbol error is **not** caused by cross-object-file
splitting. Whole-module compilation does not help. In Swift 6.4 the default-value
initializer thunk for these `@State` properties is simply not emitted/exported in a
form the referencing init can link against — so the fix must **remove the
dependency on that thunk entirely** at the source level. Reverted the Package.swift
change.

### Attempt 4 — remove inline `@State` defaults and initialize them in every direct initializer
**This is Attempt 2 done completely.** Attempt 2 proved that removing the inline
defaults eliminates the linker error; it only "failed" because not every direct
initializer was updated. There are exactly **three** direct (non-delegating)
initializers of `_ObjectHeader` that must set the six `@State` properties:

| # | File | Init |
|---|------|------|
| 1 | `_generated/…/API/_ObjectHeader+API.generated.swift:45`  | struct-body `init(@ViewBuilder title: …, …, detailContent:)` |
| 2 | `_generated/…/API/_ObjectHeader+API.generated.swift:182` | `extension … init(title: String, …, detailContent:)` |
| 3 | `Views/_ObjectHeader+View.swift:26`                        | `extension … init(title: String, …, headerChart:)` |

(`init(model:detailContent:)` delegates to #1, so it needs no change.)

**Change:**
1. In `_ObjectHeader+API.generated.swift`, change the six property declarations
   from `@State var x: T = <default>` to `@State var x: T` (no inline default).
2. Add the six `self._x = State(initialValue: <same default>)` assignments to each
   of the three direct initializers, using each property's original default value.

All assigned values are identical to the former inline defaults, so runtime
behaviour is unchanged.

**Result:** ⚠️ The two initializers in `_ObjectHeader+API.generated.swift`
(same file as the property declarations) compiled fine, but the extension
initializer in `_ObjectHeader+View.swift` (a **different file**) failed with:
```
error: '_rightViewSize' is inaccessible due to 'private' protection level
… (same for the other five @State backing stores)
```

**This finally reveals the true root cause.** A `@State` property's synthesized
backing store (`_rightViewSize`, …) is **`private`**, so it is only accessible
*within the same file*. The original Xcode-27 linker failure was the link-time
symptom of exactly this: the public `init(…headerChart:)` lives in
`_ObjectHeader+View.swift` and relied on the compiler-synthesized default-value
initializer for those private `@State` stores declared in another file. Swift 6.1
(Xcode 26) emitted/exported a thunk that let this resolve at link time; Swift 6.4
(Xcode 27) no longer does → "Undefined symbols". Same-file initializers never had
the problem, which is why only the `View.swift` init appears in the error.

So the cross-file init cannot touch `_rightViewSize` directly, and it cannot rely
on the (now unlinkable) synthesized default-value initializer either.

### Attempt 5 — same-file `internal mutating` helper that seeds the `@State` defaults
**Design:** Keep the inline defaults **removed** (so no unlinkable default-value
thunk is generated). Add one `internal mutating func` **in the same file as the
property declarations** (`_ObjectHeader+API.generated.swift`) that assigns the six
`@State` stores to their former defaults. Because the helper is in that file, it
*can* access the `private` backing stores. Every direct initializer then simply
calls this helper:
- the two same-file inits call it (they could assign directly, but using the
  helper keeps all six defaults defined in one place);
- the cross-file `View.swift` init calls it too — it never names the private
  stores, so no access-level violation and no reliance on a cross-file thunk.

This is minimal, keeps the defaults in exactly one place, and changes no runtime
behaviour.
**Result:** ❌ Did not compile — a `mutating func` cannot be *called* from an
initializer until **all** stored properties are already initialized (Swift's
definite-initialization rule), and the `@State` stores are precisely what the
helper is meant to initialize. Chicken-and-egg. Abandoned the helper idea.

### Attempt 6 (SUCCESS ✅) — move the cross-file initializer into the file that declares the properties
**Design:** The only initializer that ever failed is the public
`init(title:…headerChart:)` in `_ObjectHeader+View.swift` — because it is in a
**different file** from the `@State` declarations and therefore depends on the
cross-file (now unlinkable) default-value initializer of the private backing
stores. The two initializers in `_ObjectHeader+API.generated.swift` already live in
the same file as the declarations and were never affected.

So the fix is to put the failing initializer in the same file as the declarations:
1. **Keep** the inline `@State` defaults on the declarations (no behavioural or API
   change).
2. **Remove** the `init(title:…headerChart:)` from `_ObjectHeader+View.swift`,
   leaving an explanatory comment in its place.
3. **Add** that exact initializer — verbatim body — to
   `_ObjectHeader+API.generated.swift` as its own
   `public extension _ObjectHeader where … DetailContent == HeaderChart`.

Because the initializer is now compiled in the same file as the `@State`
declarations, the compiler resolves their default-value initializers locally and
emits no cross-file symbol → nothing for the linker to miss.

**Files changed**
- `cloud-sdk-ios-fiori-26.8.4/Sources/FioriSwiftUICore/Views/_ObjectHeader+View.swift`
  — removed the `init(title:…headerChart:)` extension (comment left behind).
- `cloud-sdk-ios-fiori-26.8.4/Sources/FioriSwiftUICore/_generated/ViewModels/API/_ObjectHeader+API.generated.swift`
  — added the same initializer (unchanged body); inline `@State` defaults retained.

No changes to the app target, to `Package.swift`, or to build settings. No public
API change (the initializer keeps the same signature, access level, and generic
constraints — only its source file moved).

**Result:** ✅ **BUILD SUCCEEDED** with Xcode 27.1.
- Incremental build: `** BUILD SUCCEEDED **` (23.3 s).
- **Clean full rebuild from scratch** (`xcodebuild clean` then build with empty
  DerivedData): `** BUILD SUCCEEDED ** [191.5 s]`, exit 0 — the success criterion.

---

## Summary of the root cause

A `@State` property's synthesized backing store (`_leftViewSize`, …) is **`private`**
— reachable only within its own source file. `_ObjectHeader`'s public
`init(title:…headerChart:)` lived in a *different* file and relied on the
compiler-synthesized default-value initializer for those private stores.

- **Xcode 26 / Swift 6.1:** emitted a thunk that let that cross-file dependency
  resolve at link time → build succeeded.
- **Xcode 27 / Swift 6.4:** no longer emits/exports that thunk in a linkable form →
  `Undefined symbols … _leftViewSize …` at link time.

The fix co-locates the initializer with the property declarations so the defaults
resolve within one file and no cross-file symbol is needed. Whole-module
compilation does **not** help (verified), confirming the problem is symbol
emission/visibility, not object-file layout.
