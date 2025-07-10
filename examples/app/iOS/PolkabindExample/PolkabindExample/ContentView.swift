//
//  ContentView.swift
//  PolkabindExample
//
//  Created by Wassim Mansouri on 10/07/2025.
//

import Polkabind
import SwiftUI

struct ContentView: View {
    @State private var destHex =
        "0x8eaf04151687736326c9fea17e25fc5287613693c912909cb226aa4794f26a48"
    @State private var amountText = "1000000000000"
    @State private var status = "Ready"

    var body: some View {
        NavigationView {
            Form {
                Section("Transfer") {
                    TextField("Destination hex", text: $destHex)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                    TextField("Amount", text: $amountText)
                        .keyboardType(.numberPad)
                }
                Section {
                    Button("Send Transfer") {
                        sendTransfer()
                    }
                }
                Section("Status") {
                    Text(status)
                        .foregroundColor(status.hasPrefix("✅") ? .green : .red)
                }
            }
            .navigationTitle("Polkabind Demo")
        }
    }

    private func sendTransfer() {
        print("🔔 sendTransfer() called")
        guard let amt = UInt64(amountText) else {
            status = "❌ Bad amount"
            return
        }
        status = "⏳ Sending…"

        DispatchQueue.global(qos: .userInitiated).async {
            print("🔔 Background task starting…")
            let result: Result<Void, Error> = Result {
                try Polkabind.doTransfer(destHex: destHex, amount: amt)
            }
            DispatchQueue.main.async {
                switch result {
                case .success:
                    print("🔔 Background succeeded")
                    status = "✅ Success!"
                case .failure(let err):
                    print("🔔 Background failed: \(err)")
                    status = "❌ \(err)"
                }
            }
        }
    }
}
