# Xcode27Issue

iOS app in Xcode27Issue.xcodeproj can be compiled successfully with 26.0.1 (17A400). See respective logs in Xcode26CompilationResults folder.

Same xcodeproj cannot be compiled with Xcode Version 27.1 due to varios linker errors

```
Undefined symbols for architecture arm64:

Xcode27Issue/cloud-sdk-ios-fiori-26.8.4/Package.swift:1:1 Undefined symbol: variable initialization expression of FioriSwiftUICore._ObjectHeader.(_leftViewSize in _45A7B69DFEEEA7E39AFAD6BB6D54C7C8) : SwiftUI.State<__C.CGSize>

Xcode27Issue/cloud-sdk-ios-fiori-26.8.4/Package.swift:1:1 Undefined symbol: variable initialization expression of FioriSwiftUICore._ObjectHeader.(_mainViewSize in _45A7B69DFEEEA7E39AFAD6BB6D54C7C8) : SwiftUI.State<__C.CGSize>

Xcode27Issue/cloud-sdk-ios-fiori-26.8.4/Package.swift:1:1 Undefined symbol: variable initialization expression of FioriSwiftUICore._ObjectHeader.(_rightViewSize in _45A7B69DFEEEA7E39AFAD6BB6D54C7C8) : SwiftUI.State<__C.CGSize>

Xcode27Issue/cloud-sdk-ios-fiori-26.8.4/Package.swift:1:1 Undefined symbol: variable initialization expression of FioriSwiftUICore._ObjectHeader.(_middleViewSize in _45A7B69DFEEEA7E39AFAD6BB6D54C7C8) : SwiftUI.State<__C.CGSize>

Xcode27Issue/cloud-sdk-ios-fiori-26.8.4/Package.swift:1:1 Undefined symbol: variable initialization expression of FioriSwiftUICore._ObjectHeader.(_statusViewSize in _45A7B69DFEEEA7E39AFAD6BB6D54C7C8) : SwiftUI.State<__C.CGSize>

Xcode27Issue/cloud-sdk-ios-fiori-26.8.4/Package.swift:1:1 Undefined symbol: variable initialization expression of FioriSwiftUICore._ObjectHeader.(_currentTabIndex in _45A7B69DFEEEA7E39AFAD6BB6D54C7C8) : SwiftUI.State<Swift.Int>

Xcode27Issue/cloud-sdk-ios-fiori-26.8.4/Package.swift:1:1 Linker command failed with exit code 1 (use -v to see invocation)
```

See Xcode27CompilationResults folder for full logs.
