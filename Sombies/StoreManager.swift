import SwiftUI
import StoreKit
import Combine

@MainActor
class StoreManager: ObservableObject {
    @Published var coins: Double = UserDefaults.standard.double(forKey: "Coins")
    
    private var updateListenerTask: Task<Void, Error>? = nil
    
    init() {
        startTransactionListener()
    }
    
    deinit {
        updateListenerTask?.cancel()
        print("Aus die Maus")
    }
    
    func startTransactionListener() {
        print("Starte beim Zuhören nach Transaktionen")
        updateListenerTask = Task.detached {
            for await result in Transaction.updates {
                print(result)
                do {
                    let checkResult = try await self.checkVerified(result)
                    await MainActor.run {
                        self.deliverCoins(for: checkResult.appTransactionID)
                    }
                    await checkResult.finish()
                    
                } catch {
                    print("Transaktions-Verifizierung fehlgeschlagen: \(error)")
                }
            }
        }
    }
    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified(_, let error):
            throw error
        case .verified(let safe):
            return safe
        }
    }
    private func deliverCoins(for transaction: String) {
        self.coins = UserDefaults.standard.double(forKey: "Coins")
        print("check \(transaction)")
        switch transaction {
        case "Sombies.Purchases.100Coins":
            self.coins += 100
        default:
            self.coins = self.coins
        }
        DispatchQueue.main.async {
            UserDefaults.standard.set(self.coins, forKey: "Coins")
        }
        print("Erfolgreich! Neuer Münzstand: \(self.coins)")
    }
    func buy(productID: String) async {
        do {
            let products = try await Product.products(for: [productID])
            if let coinProduct = products.first {
                let result = try await coinProduct.purchase()
                if case .success(let verification) = result {
                    if case .verified(let transaction) = verification {
                        self.deliverCoins(for: transaction.productID)
                        await transaction.finish()
                    }
                }
            }
        } catch {
            print("Manueller Kauf fehlgeschlagen: \(error)")
        }
    }
}

struct ShopView: View {
    var body: some View {
        StoreView(ids: ["Sombies.Purchases.100Coins"]) { product in
            Image(systemName: "brain.fill")
        }
    }
}
