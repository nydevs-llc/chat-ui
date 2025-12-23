//
//  Created by Alex.M on 23.06.2022.
//

import Foundation
import SwiftUI

struct CustomFocus<T: Hashable>: ViewModifier {
    @Binding var binding: T
    @FocusState var focus: Bool
    var equals: T

    init(_ binding: Binding<T>, equals: T) {
        self._binding = binding
        self.equals = equals
        self.focus = (binding.wrappedValue == equals)
    }

    func body(content: Content) -> some View {
        content
            .focused($focus, equals: true)
            .onChange(of: binding) { oldValue, newValue in
                focus = (newValue == equals)
            }
            .onChange(of: focus) { oldValue, newValue in
                if newValue {
                    binding = equals
                }
            }
    }
}

extension View {
    func customFocus<Value>(_ binding: Binding<Value>, equals value: Value) -> some View where Value : Hashable {
        modifier(CustomFocus(binding, equals: value))
    }
}
