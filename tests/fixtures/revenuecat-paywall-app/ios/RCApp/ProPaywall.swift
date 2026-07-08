import SwiftUI
import RevenueCat
import RevenueCatUI

// RevenueCat remote-configured paywall: the Restore / Terms / Privacy controls
// are rendered by the SDK from the dashboard configuration, so none of them
// appear in app source. The scanner must not hard-FAIL the 3.1.2 link checks
// here — it should WARN to verify the dashboard paywall instead.
struct ProPaywall: View {
  var body: some View {
    PaywallView(displayCloseButton: true)
  }
}
