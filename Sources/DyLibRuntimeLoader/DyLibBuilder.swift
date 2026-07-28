//
//  Created by Winston Du on 17/7/26.
//

import Foundation

class DyLibBuilder<T> {

    private let factory: () -> T

    init(factory: @autoclosure @escaping () -> T) {
        self.factory = factory
    }

    func build() -> T {
        return factory()
    }
}
