//
//  ContentView.swift
//  Xcode27Issue
//
//  Created by Marco Eidinger on 10/30/26.
//

import SwiftUI
import FioriSwiftUICore
import FioriThemeManager

struct ContentView: View {
    var body: some View {
        VStack {
            Button {} label: {
                FioriIcon.actions.thumbUp
            }
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
